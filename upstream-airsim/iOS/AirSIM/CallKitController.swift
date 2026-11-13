import AVFoundation
import CallKit

enum CallKitSynchronizationPolicy {
    static func mayFinishEndedHistory(currentBackendID: String?, endedID: String) -> Bool {
        currentBackendID == endedID
    }
}
import Foundation

/// Put the system CallKit The operation is forwarded to the module control layer，The protocol is restricted to the main thread to protect AppModel state。
@MainActor
protocol CallKitActionHandling: AnyObject {
    func callKitPrepareAudioSession() throws
    func callKitStart(number: String) async throws
    func callKitAnswer(origin: CallAnswerOrigin) async throws
    func callKitEnd() async throws
    func callKitSetMuted(_ muted: Bool) async
    func callKitPlayDTMF(_ digits: String) async throws
    func callKitAnswer(uuid: UUID, origin: CallAnswerOrigin) async throws
    func callKitEnd(uuid: UUID) async throws
    func callKitSetMuted(_ muted: Bool, uuid: UUID) async
    func callKitPlayDTMF(_ digits: String, uuid: UUID) async throws
    func callKitAudioSessionDidActivate() async
    func callKitAudioSessionDidDeactivate()
    func callKitProviderDidReset() async
    func callKitDidFail(_ message: String)
    func callKitDidReceiveIncoming(_ call: IncomingVoIPCall)
    func callKitCallDidEnd()
}

enum CallAnswerOrigin: Equatable, Sendable {
    case system
    case app
}

/// CallKit system transactions must precede the slow Agent/Relay I/O Finish，The system will be activated in time
/// AVAudioSession。Backend errors are returned individually，Ending of established system call by caller。
enum CallKitActionCoordinator {
    static func perform(
        prepare: () throws -> Void,
        fulfill: () -> Void,
        backend: () async throws -> Void
    ) async throws -> Error? {
        try prepare()
        fulfill()
        do {
            try await backend()
            return nil
        } catch {
            return error
        }
    }
}

enum CallKitEndActionPolicy {
    static func shouldForwardToBackend(systemCallWasCurrent: Bool) -> Bool {
        systemCallWasCurrent
    }
}

extension CallKitActionHandling {
    func callKitAnswer(uuid: UUID, origin: CallAnswerOrigin) async throws { try await callKitAnswer(origin: origin) }
    func callKitEnd(uuid: UUID) async throws { try await callKitEnd() }
    func callKitSetMuted(_ muted: Bool, uuid: UUID) async { await callKitSetMuted(muted) }
    func callKitPlayDTMF(_ digits: String, uuid: UUID) async throws { try await callKitPlayDTMF(digits) }
    func callKitPrepareAudioSession() throws {}
    func callKitDidReceiveIncoming(_ call: IncomingVoIPCall) {}
    func callKitCallDidEnd() {}
}

/// After hanging up PushKit、Local long polling and system callbacks may arrive out of order。Short-term reservation has ended
/// call_id/UUID，Avoid the same phone call CallKit After being closed, it was reopened due to the late arrival event.。
struct IncomingCallDeduplicator {
    let retention: TimeInterval
    private var endedCallIDs: [String: Date] = [:]
    private var endedUUIDs: [UUID: Date] = [:]

    init(retention: TimeInterval = 90) {
        self.retention = retention
    }

    mutating func recordEnded(callID: String?, uuid: UUID?, at date: Date = Date()) {
        purgeExpired(now: date)
        if let callID, !callID.isEmpty { endedCallIDs[callID] = date }
        if let uuid { endedUUIDs[uuid] = date }
    }

    mutating func shouldAccept(callID: String?, uuid: UUID?, now: Date = Date()) -> Bool {
        purgeExpired(now: now)
        if let callID, endedCallIDs[callID] != nil { return false }
        if let uuid, endedUUIDs[uuid] != nil { return false }
        return true
    }

    private mutating func purgeExpired(now: Date) {
        endedCallIDs = endedCallIDs.filter { now.timeIntervalSince($0.value) <= retention }
        endedUUIDs = endedUUIDs.filter { now.timeIntervalSince($0.value) <= retention }
    }
}

/// Maintenance module call and system call UUID one-to-one mapping，And undertake the operation of lock screen and system call interface。
@MainActor
final class CallKitController: NSObject {
    static let shared = CallKitController()

    private let provider: CXProvider
    private let callController = CXCallController()
    private(set) var audioSessionIsActive = false
    private var entitlementAvailable = true
    private var featureEnabled = ConnectionModeRuntimePolicy(mode: ConnectionModePreference.selected()).usesCallKit
    weak var handler: (any CallKitActionHandling)?

    private var currentUUID: UUID?
    private var currentBackendID: String?
    private var currentAgentID: String?
    private var currentState: String?
    private var currentNumber: String?
    private var currentDirection: String?
    private var incomingReportRequested = false
    private var incomingReportFailed = false
    private var systemCallReported = false
    private var endActionFulfilled = false
    private var missingCallPolls = 0
    private var outgoingStartInFlight = false
    private var outgoingStartID = UUID()
    private var handledOutgoingActions: Set<ObjectIdentifier> = []
    private var dialedOutgoingUUIDs: Set<UUID> = []
    private var appAnswerRequestUUID: UUID?
    private var acceptedAnswerUUID: UUID?
    private var incomingReportCompletions: [(Error?) -> Void] = []
    private var incomingSystemReporter: RequiredSystemReporter?
    private var incomingDeduplicator = IncomingCallDeduplicator()
    private(set) var currentIncomingPush: IncomingVoIPCall?

    override convenience init() {
        self.init(observesSystemCallbacks: true)
    }

    /// Synthetic report callbacks in unit tests must not race the simulator's
    /// unrelated provider reset. Production always observes the real provider.
    init(observesSystemCallbacks: Bool) {
        let configuration = CXProviderConfiguration()
        configuration.maximumCallGroups = 1
        configuration.maximumCallsPerCallGroup = 1
        configuration.supportedHandleTypes = [.phoneNumber, .generic]
        configuration.supportsVideo = false
        configuration.includesCallsInRecents = true
        provider = CXProvider(configuration: configuration)
        super.init()
        if observesSystemCallbacks { provider.setDelegate(self, queue: .main) }
    }

    deinit {
        provider.invalidate()
    }

    var isAvailable: Bool { entitlementAvailable && featureEnabled }

    func setEnabled(_ enabled: Bool) {
        guard featureEnabled != enabled else { return }
        featureEnabled = enabled
        guard !enabled else { return }
        if let uuid = currentUUID, systemCallReported {
            provider.reportCall(with: uuid, endedAt: Date(), reason: .failed)
        }
        audioSessionIsActive = false
        resetCurrentCall()
#if DEBUG
        debugLog("Local mode is turned off for CallKit")
#endif
    }

    var managesCurrentCall: Bool {
        isAvailable && currentUUID != nil && (systemCallReported || currentDirection == "outgoing")
    }

    var currentCallIsAnswered: Bool {
        (currentUUID != nil && acceptedAnswerUUID == currentUUID)
            || ["active", "held"].contains(currentState)
    }

    /// Expose only immutable identities，The life cycle state consists of CallLifecycleStore Unified management。
    var currentSystemCallUUID: UUID? { currentUUID }

    var suppressesInAppIncomingRingtone: Bool {
        incomingReportRequested && !incomingReportFailed
    }

    func watchCallUUID(for backendID: String?) -> UUID? {
        guard backendID == nil || backendID == currentBackendID else { return nil }
        return currentUUID
    }

    func matchesCurrentCall(callID: String?, uuid: UUID?, agentID: String? = nil,
                            generation: UInt64? = nil) -> Bool {
        guard currentUUID != nil else { return false }
        guard callID != nil || uuid != nil else { return false }
        if let agentID, agentID != (currentAgentID ?? currentIncomingPush?.agentID) { return false }
        if let generation, let pushed = currentIncomingPush,
           generation != pushed.generation { return false }
        let backendMatches = callID == nil || callID == currentBackendID
        let uuidMatches = uuid == nil || uuid == currentUUID
        return backendMatches && uuidMatches
    }

    /// After the paired device takes over the same call，Terminate this machine immediately CallKit，Avoid simultaneous ringing at both ends or media preemption。
    func reportCurrentCallEnded(reason: CXCallEndedReason) {
        finishCurrentCall(previous: nil, reason: reason)
    }
    func withdrawLocalPresentation(uuid: UUID, reason: CXCallEndedReason = .unanswered) {
        guard currentUUID == uuid, currentState == "incoming" else { return }
        if systemCallReported { provider.reportCall(with: uuid, endedAt: Date(), reason: reason) }
        resetCurrentCall() // No backend command and no global call-ended handler.
    }

    func reportCurrentOutgoingConnected() {
        guard currentDirection == "outgoing", let uuid = currentUUID,
              currentState != "active", systemCallReported else { return }
        currentState = "active"
        provider.reportOutgoingCall(with: uuid, connectedAt: Date())
    }
    func synchronizeOwnedCall(_ call: CallRecord, uuid: UUID, agentID: String) {
        guard currentUUID == uuid else { return }
        currentAgentID = agentID
        synchronize(call: call, previous: nil, callerName: nil)
    }

    /// PushKit A cold start must immediately hand over the same real incoming call to the system。Subsequent local status synchronization will be reused.
    /// call_id/UUID，No second incoming system call will be generated。
    func reportIncomingPush(
        _ call: IncomingVoIPCall,
        systemReport: RequiredSystemReporter? = nil,
        completion: @escaping (Error?) -> Void
    ) {
        guard isAvailable else {
            completion(CallKitBridgeError.unavailable)
            return
        }
        guard incomingDeduplicator.shouldAccept(callID: call.callID, uuid: call.uuid) else {
            debugLog("Ignore late PushKit events for ended calls")
            completion(nil)
            return
        }
        if currentUUID != nil {
            guard call.matches(backendID: currentBackendID, uuid: currentUUID) else {
                completion(CallKitBridgeError.callInProgress)
                return
            }
            currentIncomingPush = call
            currentBackendID = call.callID
            currentNumber = call.number ?? currentNumber
            if systemCallReported {
                handler?.callKitDidReceiveIncoming(call)
                completion(nil)
                return
            }
            incomingReportCompletions.append(completion)
            reportIncomingIfNeeded(number: currentNumber, callerName: call.callerName,
                                   source: "PushKit resubmission", genericHandle: call.isVirtual)
            handler?.callKitDidReceiveIncoming(call)
            return
        }

        incomingSystemReporter = systemReport
        currentUUID = call.uuid
        currentBackendID = call.callID
        currentIncomingPush = call
        currentDirection = "incoming"
        currentState = "incoming"
        currentNumber = call.number
        missingCallPolls = 0
        endActionFulfilled = false
        incomingReportCompletions.append(completion)
        reportIncomingIfNeeded(number: call.number, callerName: call.callerName,
                               source: "PushKit", genericHandle: call.isVirtual)
        handler?.callKitDidReceiveIncoming(call)
    }

    typealias RequiredSystemReporter = (UUID, CXCallUpdate, @escaping (Error?) -> Void) -> Void
    /// A genuine VoIP push is still reported even if local mode is selected or
    /// another device owns the primary call. Never reset/retarget that primary.
    func reportRequiredVoIPPush(_ call: IncomingVoIPCall,
        systemReport: RequiredSystemReporter? = nil, systemEnd: ((UUID) -> Void)? = nil,
        completion: @escaping (Error?) -> Void) {
        // Watch may own the shared route without an iPhone CallKit UUID.
        // Native presentation state alone is therefore not an admission gate.
        let model = handler as? AppModel
        if currentUUID != nil,
           ((currentUUID == call.uuid || (call.agentID != nil && currentIncomingPush?.agentID == call.agentID))
                && currentIncomingPush?.callID == call.callID
                || model?.ownsSystemPresentation(for: call) == true) {
            // This real call is already reported. Reporting and then ending the
            // duplicate UUID would otherwise end the active CallKit surface.
            PushDiagnostics.record("PushKit reuses existing call sessions", fields: ["call_uuid": currentUUID!.uuidString])
            completion(nil)
            return
        }
        let localOwnerBusy = model?.ownsLocalCallPresentation == true
            || model?.cloudCallOwnsPrimaryPresentation == true
            || model?.deviceCallContext.admissionReservation != nil
        if isAvailable, CloudSignalingPreference.isEnabled(),
           !localOwnerBusy,
           currentUUID == nil || currentUUID == call.uuid,
           incomingDeduplicator.shouldAccept(callID: call.callID, uuid: call.uuid) {
            reportIncomingPush(call, completion: completion)
            return
        }
        let report: RequiredSystemReporter = systemReport ?? { [provider] uuid, update, done in
            provider.reportNewIncomingCall(with: uuid, update: update, completion: done)
        }
        let end = systemEnd ?? { [provider] uuid in
            provider.reportCall(with: uuid, endedAt: Date(), reason: .unanswered)
        }
        PushDiagnostics.record("PushKit incoming calls do not enter the main call display", fields: [
            "callkit_available": String(isAvailable),
            "signaling_enabled": String(CloudSignalingPreference.isEnabled()),
            "local_owner_busy": String(localOwnerBusy),
            "system_call_exists": String(currentUUID != nil)])
        report(call.uuid, update(number: call.number, callerName: call.callerName,
                                 genericHandle: call.isVirtual)) { error in
            Task { @MainActor in
                if error == nil { end(call.uuid) }
                completion(error)
            }
        }
    }

    /// Let the system take over the outbound transaction first；real module ATD can only be CXProvider delegate Execute in callback。
    func startOutgoingCall(number: String, intentID: UUID = UUID(),
        systemStart: ((CXStartCallAction) async throws -> Void)? = nil) async throws {
        guard isAvailable else { throw CallKitBridgeError.unavailable }
        guard currentUUID == nil else { throw CallKitBridgeError.callInProgress }

        let uuid = intentID
        currentUUID = uuid
        currentDirection = "outgoing"
        currentNumber = number
        currentState = "dialing"
        missingCallPolls = 0
        endActionFulfilled = false

        do {
            let handle = CallKitNumberPresentation.handle(number: number)
            let action = CXStartCallAction(call: uuid, handle: handle)
            if let systemStart { try await systemStart(action) } else { try await request(action) }
        } catch {
            let unavailable = disableCallKitIfUnentitled(error)
            resetCurrentCall()
            if unavailable { throw CallKitBridgeError.unavailable }
            throw error
        }
    }

    func answerCurrentCall(presentInApp: Bool = false) async throws {
        guard let uuid = currentUUID, systemCallReported else {
            throw CallKitBridgeError.noSystemCall
        }
        if presentInApp { appAnswerRequestUUID = uuid }
        do {
            try await requestSystemAction(CXAnswerCallAction(call: uuid))
        } catch {
            if appAnswerRequestUUID == uuid { appAnswerRequestUUID = nil }
            throw error
        }
    }

    func endCurrentCall() async throws {
        guard let uuid = currentUUID, systemCallReported || currentDirection == "outgoing" else {
            throw CallKitBridgeError.noSystemCall
        }
        try await requestSystemAction(CXEndCallAction(call: uuid))
    }

    func setMuted(_ muted: Bool) async throws {
        guard let uuid = currentUUID, systemCallReported else {
            throw CallKitBridgeError.noSystemCall
        }
        try await requestSystemAction(CXSetMutedCallAction(call: uuid, muted: muted))
    }

    /// App The inner keyboard also goes CallKit affairs，Ensure that the system call page and App Each page will not maintain its own set DTMF state。
    func playDTMF(_ digits: String) async throws {
        guard let uuid = currentUUID, systemCallReported else {
            throw CallKitBridgeError.noSystemCall
        }
        let validDigits = digits.filter { "0123456789*#".contains($0) }
        guard !validDigits.isEmpty else { return }
        try await requestSystemAction(
            CXPlayDTMFCallAction(call: uuid, digits: validDigits, type: .singleTone)
        )
    }

    /// After each module polling, the incoming and outgoing call life cycles are synchronized to the system.。
    func synchronize(call: CallRecord?, previous: CallRecord?, callerName: String?) {
        // CallKit Only retained after permission is denied by the system App internal state machine，Cannot continue to fake system calls UUID。
        guard isAvailable else {
            if call == nil { resetCurrentCall() }
            return
        }
        guard let call else {
            // module has put the same ID write tape ended_at 的 history，This is a definite end event，
            // System calls must be closed immediately，No more waiting for empty CLCC Anti-shake。
            if previous?.endedAt != nil {
                guard let previous,
                      CallKitSynchronizationPolicy.mayFinishEndedHistory(
                        currentBackendID: currentBackendID, endedID: previous.id
                      ) else { return }
                finishCurrentCall(previous: previous)
                return
            }
            // AT+CLCC Occasional empty responses do not mean the call has been hung up；reserve UUID，Avoid system speakers/Silent transaction becomes unknown UUID。
            if currentDirection == "outgoing", outgoingStartInFlight { return }
            if currentUUID != nil, systemCallReported || currentDirection == "outgoing" {
                missingCallPolls += 1
                guard missingCallPolls >= 3 else { return }
            }
            finishCurrentCall(previous: previous)
            return
        }

        if call.direction == "outgoing" {
            // Only sync by startOutgoingCall Created system call out；not external ATD forgery UUID。
            guard currentDirection == "outgoing", let uuid = currentUUID else { return }
            if let backendID = currentBackendID, backendID != call.id {
                finishCurrentCall(previous: previous, reason: .failed)
                return
            }
            currentBackendID = call.id
            currentNumber = call.number ?? currentNumber
            missingCallPolls = 0
            if call.state == "active", currentState != "active", systemCallReported {
                provider.reportOutgoingCall(with: uuid, connectedAt: call.updatedAt)
            }
            currentState = call.state
            return
        }

        if currentDirection == "outgoing" {
            finishCurrentCall(previous: previous, reason: .failed)
        }

        missingCallPolls = 0
        outgoingStartInFlight = false

        if let backendID = currentBackendID, backendID != call.id {
            finishCurrentCall(previous: previous, reason: .failed)
        }
        if currentUUID == nil,
           !incomingDeduplicator.shouldAccept(callID: call.id, uuid: nil) {
            debugLog("Ignore late module status for ended calls")
            return
        }
        if currentUUID == nil { currentUUID = UUID() }
        currentDirection = "incoming"
        currentBackendID = call.id
        currentNumber = call.number

        if ["incoming", "waiting"].contains(call.state) {
            reportIncomingIfNeeded(number: call.number, callerName: callerName, source: "module status")
        }
        currentState = call.state
    }

    private func reportIncomingIfNeeded(number: String?, callerName: String?, source: String,
                                        genericHandle: Bool = false) {
        guard !incomingReportRequested, !systemCallReported, let uuid = currentUUID else { return }
        incomingReportRequested = true
        debugLog("Request system call interface; source=\(source)")
        let report: RequiredSystemReporter = incomingSystemReporter ?? { [provider] uuid, update, done in
            provider.reportNewIncomingCall(with: uuid, update: update, completion: done)
        }
        report(uuid, update(number: number, callerName: callerName, genericHandle: genericHandle)) { [weak self] error in
            Task { @MainActor [weak self] in
                guard let self else { return }
                guard self.currentUUID == uuid else { return }
                if let error {
                    PushDiagnostics.record("CallKit system fails to report incoming calls", error: error)
                    let diagnosticError = error as NSError
                    self.debugLog(
                        "The system fails to report incoming calls; domain=\(diagnosticError.domain) code=\(diagnosticError.code)"
                            + "message=\(diagnosticError.localizedDescription)"
                    )
                    if self.disableCallKitIfUnentitled(error) {
                        self.finishIncomingReport(error)
                        self.resetCurrentCall()
                        return
                    }
                    self.systemCallReported = false
                    self.incomingReportFailed = true
                    self.handler?.callKitDidFail("System call interface failed to start: \(error.localizedDescription)")
                    self.finishIncomingReport(error)
                } else {
                    PushDiagnostics.record("CallKit system successfully reports incoming calls")
                    self.debugLog("System call reporting successful")
                    self.systemCallReported = true
                    self.finishIncomingReport(nil)
                }
            }
        }
    }

    private func finishIncomingReport(_ error: Error?) {
        let completions = incomingReportCompletions
        incomingReportCompletions.removeAll()
        completions.forEach { $0(error) }
    }

    private func finishCurrentCall(
        previous: CallRecord?,
        reason explicitReason: CXCallEndedReason? = nil
    ) {
        guard let uuid = currentUUID else { return }
        let finishReason = explicitReason ?? endedReason(for: previous)
        Task { @MainActor in
            await AgentVerboseTraceRecorder.shared.recordEvent(
                source: "APP", category: "callkit", phase: "finish",
                title: "CallKit call ended",
                fields: [
                    "call_uuid": uuid.uuidString.lowercased(),
                    "state": self.currentState ?? "none",
                    "reason": String(finishReason.rawValue),
                    "system_reported": String(self.systemCallReported),
                ]
            )
        }
        if systemCallReported, !endActionFulfilled {
            let reason = explicitReason ?? endedReason(for: previous)
            provider.reportCall(with: uuid, endedAt: previous?.endedAt ?? Date(), reason: reason)
        }
        incomingDeduplicator.recordEnded(
            callID: currentBackendID ?? previous?.id,
            uuid: uuid,
            at: previous?.endedAt ?? Date()
        )
        handler?.callKitCallDidEnd()
        resetCurrentCall()
    }

    private func endedReason(for call: CallRecord?) -> CXCallEndedReason {
        guard let call else { return .failed }
        return call.state == "active" || call.state == "held" ? .remoteEnded : .unanswered
    }

    private func update(number: String?, callerName: String?, genericHandle: Bool) -> CXCallUpdate {
        let update = CallKitNumberPresentation.update(number: number, callerName: callerName)
        let value = number?.isEmpty == false ? number! : "unknown number"
        if genericHandle {
            // Dashboard virtual calls use a title, not a phone number. A
            // .phoneNumber handle can be rejected/blank for non-numeric text.
            let title = callerName?.isEmpty == false ? callerName! : value
            update.remoteHandle = CXHandle(type: .generic, value: title)
            update.localizedCallerName = title
        }
        update.supportsHolding = false
        update.supportsGrouping = false
        update.supportsUngrouping = false
        update.supportsDTMF = true
        update.hasVideo = false
        return update
    }

    private func request(_ action: CXAction) async throws {
        try await withCheckedThrowingContinuation {
            (continuation: CheckedContinuation<Void, Error>) in
            callController.request(CXTransaction(action: action)) { error in
                if let error { continuation.resume(throwing: error) }
                else { continuation.resume() }
            }
        }
    }

    /// CallKit May be temporarily lost during system interface rebuild UUID；Convert to business layer recoverable errors，
    /// Don't make mistakes 4 spread directly into“通话已结束”。
    private func requestSystemAction(_ action: CXAction) async throws {
        do {
            try await request(action)
        } catch {
            let nsError = error as NSError
            if nsError.domain == CXErrorDomainRequestTransaction,
               nsError.code == CXErrorCodeRequestTransactionError.Code.unknownCallUUID.rawValue {
                throw CallKitBridgeError.staleSystemCall
            }
            throw error
        }
    }

    /// Personal signatures or restricted devices may be returned requesttransaction/unentitled；Automatically used at this time App Intercom。
    private func disableCallKitIfUnentitled(_ error: Error) -> Bool {
        let error = error as NSError
        guard error.domain == CXErrorDomainRequestTransaction,
              error.code == CXErrorCodeRequestTransactionError.Code.unentitled.rawValue else {
            return false
        }
        entitlementAvailable = false
        audioSessionIsActive = false
        debugLog("CallKit was determined by the system to have no permissions and has been downgraded to in-app calling.")
        return true
    }

    /// Real machine joint debugging only records status and system error codes，Avoid writing phone numbers to device logs。
    private func debugLog(_ message: String) {
#if DEBUG
        print("[SimHelp CallKit] \(message)")
#endif
    }

    private func resetCurrentCall() {
        if !incomingReportCompletions.isEmpty {
            finishIncomingReport(CallKitBridgeError.staleSystemCall)
        }
        currentUUID = nil
        currentBackendID = nil
        currentAgentID = nil
        currentState = nil
        currentNumber = nil
        currentDirection = nil
        currentIncomingPush = nil
        incomingSystemReporter = nil
        incomingReportRequested = false
        incomingReportFailed = false
        systemCallReported = false
        endActionFulfilled = false
        missingCallPolls = 0
        outgoingStartInFlight = false
        appAnswerRequestUUID = nil
        acceptedAnswerUUID = nil
    }

    private func fail(_ action: CXAction, error: Error) {
        action.fail()
        handler?.callKitDidFail(error.localizedDescription)
    }

    private func performAnswer(_ action: CXAnswerCallAction) async {
        do {
            guard currentUUID == action.callUUID else { throw CallKitBridgeError.staleSystemCall }
            guard let handler else { throw CallKitBridgeError.handlerUnavailable }
            if acceptedAnswerUUID == action.callUUID { action.fulfill(); return }
            let origin: CallAnswerOrigin = appAnswerRequestUUID == action.callUUID ? .app : .system
            appAnswerRequestUUID = nil
            currentState = "connecting"
            // Configure the audio category before fulfilling the system answer
            // so CallKit can activate the session. A prepare failure must not
            // fail CXAnswerCallAction: the backend can still configure audio and
            // report a real transport error separately.
            do {
                try handler.callKitPrepareAudioSession()
            } catch {
                debugLog("Audio preconfiguration failed before answering, continue to answer the system: \(error.localizedDescription)")
            }
            acceptedAnswerUUID = action.callUUID
            action.fulfill()
            do {
                try await handler.callKitAnswer(uuid: action.callUUID, origin: origin)
                guard currentUUID == action.callUUID else { return }
            } catch {
                guard currentUUID == action.callUUID else { return }
                PushDiagnostics.record("CallKit failed to answer transaction", error: error, fields: [
                    "finish_source": "answer_backend_error", "failure_reason": String(describing: type(of: error)),
                    "call_id": currentBackendID ?? "none", "call_uuid": action.callUUID.uuidString,
                    "device_id": currentIncomingPush?.agentID ?? "none",
                    "generation": String(currentIncomingPush?.generation ?? 0),
                    "answer_source": origin == .system ? "callkit" : "app",
                    "previous_state": currentState ?? "none", "next_state": "failed"])
                finishCurrentCall(previous: nil, reason: .failed)
                handler.callKitDidFail(error.localizedDescription)
            }
        } catch {
            fail(action, error: error)
        }
    }

    private func performStart(_ action: CXStartCallAction) async {
        if action.isComplete { return }
        let actionIdentity = ObjectIdentifier(action)
        guard handledOutgoingActions.insert(actionIdentity).inserted else { return }
        if dialedOutgoingUUIDs.contains(action.callUUID) {
            action.fulfill()
            return
        }
        if outgoingStartInFlight { return }
        if systemCallReported, currentUUID == action.callUUID, currentDirection == "outgoing" {
            action.fulfill()
            return
        }
        outgoingStartInFlight = true
        let operationID = UUID()
        outgoingStartID = operationID
        defer { if outgoingStartID == operationID { outgoingStartInFlight = false } }
        do {
            guard let handler else { throw CallKitBridgeError.handlerUnavailable }
            // Apart from App Transactions submitted within，The system may also pass Siri/联系人把呼出动作
            // Give it directly to provider；At this time, the system UUID Create the same set of states。
            if currentUUID == nil {
                currentUUID = action.callUUID
                currentDirection = "outgoing"
                currentNumber = action.handle.value
                currentState = "dialing"
            }
            guard currentUUID == action.callUUID, currentDirection == "outgoing" else {
                throw CallKitBridgeError.staleSystemCall
            }
            dialedOutgoingUUIDs.insert(action.callUUID)
            trimOutgoingDeduplicationState(keeping: action)
            let backendError = try await CallKitActionCoordinator.perform(
                prepare: { try handler.callKitPrepareAudioSession() },
                fulfill: {
                    self.provider.reportOutgoingCall(with: action.callUUID, startedConnectingAt: Date())
                    self.systemCallReported = true
                    // give first CallKit Establish system calls and audio sessions；Cloud dial polling longest 25 Second，
                    // Can't occupy CXStartCallAction，否则系统 UI and didActivate will lag。
                    action.fulfill()
                },
                backend: { try await handler.callKitStart(number: action.handle.value) }
            )
            // A completed backend request belongs to this CXCall only. The user
            // may have ended it and started another while the request was pending.
            guard currentUUID == action.callUUID else { return }
            if let backendError {
                finishCurrentCall(previous: nil, reason: .failed)
                handler.callKitDidFail(backendError.localizedDescription)
                return
            }
            if currentState == "active" {
                provider.reportOutgoingCall(with: action.callUUID, connectedAt: Date())
            }
        } catch {
            if currentUUID == action.callUUID { resetCurrentCall() }
            fail(action, error: error)
        }
    }

    private func trimOutgoingDeduplicationState(keeping action: CXStartCallAction) {
        guard handledOutgoingActions.count > 32 || dialedOutgoingUUIDs.count > 32 else { return }
        handledOutgoingActions = [ObjectIdentifier(action)]
        dialedOutgoingUUIDs = [action.callUUID]
    }

    private func performEnd(_ action: CXEndCallAction) async {
        let currentHandler = handler
        // reportCall(ended:) may be followed by a delayed CXEndCallAction after
        // the authoritative Agent state already cleared this UUID. That action
        // is cleanup, not a new user hangup whose missing transport needs an alert.
        let systemCallWasCurrent = currentUUID == action.callUUID
        guard systemCallWasCurrent else { action.fulfill(); return }
        endActionFulfilled = true
        action.fulfill()
        var backendError: Error?
        if CallKitEndActionPolicy.shouldForwardToBackend(
            systemCallWasCurrent: systemCallWasCurrent
        ) {
            do {
                guard let currentHandler else { throw CallKitBridgeError.handlerUnavailable }
                try await currentHandler.callKitEnd(uuid: action.callUUID)
            } catch {
                backendError = error
            }
        }

        // CallKit owns the local system-call lifecycle. A temporarily missing
        // module must not leave the UUID registered after the user hangs up.
        guard currentUUID == action.callUUID else { return }
        incomingDeduplicator.recordEnded(
            callID: currentBackendID,
            uuid: currentUUID,
            at: Date()
        )
        currentHandler?.callKitCallDidEnd()
        resetCurrentCall()

        if let backendError {
            currentHandler?.callKitDidFail(backendError.localizedDescription)
        }
    }
}

extension CallKitController: CXProviderDelegate {
    nonisolated func providerDidReset(_ provider: CXProvider) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.audioSessionIsActive = false
            await self.handler?.callKitProviderDidReset()
            self.resetCurrentCall()
        }
    }

    nonisolated func provider(_ provider: CXProvider, perform action: CXStartCallAction) {
        Task { @MainActor [weak self] in await self?.performStart(action) }
    }

    nonisolated func provider(_ provider: CXProvider, perform action: CXAnswerCallAction) {
        Task { @MainActor [weak self] in await self?.performAnswer(action) }
    }

    nonisolated func provider(_ provider: CXProvider, perform action: CXEndCallAction) {
        Task { @MainActor [weak self] in await self?.performEnd(action) }
    }

    nonisolated func provider(_ provider: CXProvider, perform action: CXSetMutedCallAction) {
        Task { @MainActor [weak self] in
            guard let self, let handler = self.handler else {
                action.fail()
                return
            }
            guard self.currentUUID == action.callUUID else { action.fail(); return }
            await handler.callKitSetMuted(action.isMuted, uuid: action.callUUID)
            action.fulfill()
        }
    }

    nonisolated func provider(_ provider: CXProvider, perform action: CXPlayDTMFCallAction) {
        Task { @MainActor [weak self] in
            do {
                guard let handler = self?.handler else { throw CallKitBridgeError.handlerUnavailable }
                guard self?.currentUUID == action.callUUID else { throw CallKitBridgeError.staleSystemCall }
                try await handler.callKitPlayDTMF(action.digits, uuid: action.callUUID)
                action.fulfill()
            } catch {
                self?.fail(action, error: error)
            }
        }
    }

    nonisolated func provider(
        _ provider: CXProvider,
        didActivate audioSession: AVAudioSession
    ) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.audioSessionIsActive = true
            await AgentVerboseTraceRecorder.shared.recordEvent(
                source: "APP",
                category: "callkit-audio",
                phase: "activated",
                title: "CallKit audio session activated",
                fields: self.audioTraceFields(audioSession)
            )
            await self.handler?.callKitAudioSessionDidActivate()
        }
    }

    nonisolated func provider(
        _ provider: CXProvider,
        didDeactivate audioSession: AVAudioSession
    ) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.audioSessionIsActive = false
            await AgentVerboseTraceRecorder.shared.recordEvent(
                source: "APP",
                category: "callkit-audio",
                phase: "deactivated",
                title: "CallKit audio session is disabled",
                fields: self.audioTraceFields(audioSession)
            )
            self.handler?.callKitAudioSessionDidDeactivate()
        }
    }

    private func audioTraceFields(_ audioSession: AVAudioSession) -> [String: String] {
        let inputs = audioSession.currentRoute.inputs.map { $0.portType.rawValue }.joined(separator: ",")
        let outputs = audioSession.currentRoute.outputs.map { $0.portType.rawValue }.joined(separator: ",")
        return [
            "call_uuid": currentUUID?.uuidString.lowercased() ?? "none",
            "state": currentState ?? "none",
            "input_route": inputs.isEmpty ? "none" : inputs,
            "output_route": outputs.isEmpty ? "none" : outputs,
            "sample_rate": String(Int(audioSession.sampleRate)),
            "io_buffer_ms": String(Int(audioSession.ioBufferDuration * 1_000)),
        ]
    }
}

enum CallKitBridgeError: LocalizedError {
    case noSystemCall
    case staleSystemCall
    case handlerUnavailable
    case unavailable
    case callInProgress
    case noReachableTransport
    case cloudMediaDisabled

    var errorDescription: String? {
        switch self {
        case .noSystemCall: return "System call has not been established yet"
        case .staleSystemCall: return "System call status has been refreshed"
        case .handlerUnavailable: return "Call controller is not ready yet"
        case .unavailable: return "System CallKit is currently unavailable"
        case .callInProgress: return "There is currently an ongoing system call"
        case .noReachableTransport: return "Samsung local link and cloud voice are currently unreachable"
        case .cloudMediaDisabled: return "Samsung local link is unreachable and cloud voice relay is closed"
        }
    }
}
