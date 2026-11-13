import Foundation
import Network
import CryptoKit

struct SamsungManualPairingAddress: Equatable, Sendable {
    let host: String
    let port: UInt16
    let usesTLS: Bool
    let remoteControlPort: UInt16?
    let remotePCMPort: UInt16?
    init(host: String, port: String, usesTLS: Bool = false,
         controlPort: String? = nil, pcmPort: String? = nil) throws {
        let host = host.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let portText = port.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (usesTLS ? RemoteDirectHost.isValid(host) : VoWLANEndpoint.permitsDirectIPv4(host)), !portText.isEmpty,
              portText.utf8.allSatisfy({ (48...57).contains($0) }),
              let port = UInt16(portText), port > 0 else { throw SamsungPairingClientError.invalidAddress }
        self.host = host
        self.port = port
        self.usesTLS = usesTLS
        if usesTLS {
            let route = try RemoteDirectConfiguration.route(agentID: "pairing", host: host,
                controlPort: controlPort ?? "", pcmPort: pcmPort ?? "")
            remoteControlPort = route.controlPort
            remotePCMPort = route.pcmPort
        } else {
            remoteControlPort = nil
            remotePCMPort = nil
        }
    }
    var endpoint: NWEndpoint { .hostPort(host: .init(host), port: .init(rawValue: port)!) }
}

enum SamsungDirectRouteProof {
    static func verify(_ proof: String, secret: Data, sessionID: String, clientKey: String,
                       agentID: String, controlPort: UInt16, pcmPort: UInt16) -> Bool {
        guard secret.count >= 32, let mac = Data(base64URL: proof) else { return false }
        let canonical = "AIRSIM-DIRECT1\n\(sessionID)\n\(clientKey)\n\(agentID)\n\(controlPort)\n\(pcmPort)"
        return HMAC<SHA256>.isValidAuthenticationCode(mac, authenticating: Data(canonical.utf8),
                                                     using: SymmetricKey(data: secret))
    }
}

struct SamsungPairingService: Identifiable {
    let endpoint: NWEndpoint
    let sessionID: String
    let serverPublicKey: Data
    let expiresAt: Date

    var id: String { sessionID }
    var displayName: String {
        if case let .service(name, _, _, _) = endpoint { return name }
        return "Android Phone Bridge"
    }
}

protocol SamsungPairingBrowsing: AnyObject {
    var stateUpdateHandler: (@Sendable (NWBrowser.State) -> Void)? { get set }
    var browseResultsChangedHandler: (@Sendable (Set<NWBrowser.Result>, Set<NWBrowser.Result.Change>) -> Void)? { get set }
    func start(queue: DispatchQueue)
    func cancel()
}

extension NWBrowser: SamsungPairingBrowsing {}

@MainActor
final class SamsungPairingBrowser: ObservableObject {
    @Published private(set) var services: [SamsungPairingService] = []
    @Published private(set) var stateText = "Scanning VoWLAN LAN…"

    private let queue = DispatchQueue(label: "com.simhelp.samsung-pair.browser")
    private var browser: SamsungPairingBrowsing?
    private let makeBrowser: (NWParameters) -> SamsungPairingBrowsing
    private var scanID: UUID?

    init(makeBrowser: @escaping (NWParameters) -> SamsungPairingBrowsing = {
        NWBrowser(for: .bonjourWithTXTRecord(type: "_airsim-pair._tcp", domain: nil), using: $0)
    }) {
        self.makeBrowser = makeBrowser
    }

    func start() {
        guard browser == nil else { return }
        let scanID = UUID()
        self.scanID = scanID
        services = []
        stateText = "Scanning VoWLAN LAN…"
        let parameters = NWParameters.tcp
        parameters.includePeerToPeer = true
        let active = makeBrowser(parameters)
        active.stateUpdateHandler = { [weak self] state in
            Task { @MainActor in
                guard let self, self.scanID == scanID else { return }
                switch state {
                case .ready: self.stateText = "Waiting for Android pairing broadcast…"
                case .waiting: self.stateText = "Please make sure iPhone and Android are on the same Wi-Fi or Android hotspot"
                case .failed(let error):
                    self.stop()
                    self.stateText = "LAN scan failed: \(error.localizedDescription) . Please check the local NetworkPermission and scan again."
                case .cancelled: self.stop()
                default: break
                }
            }
        }
        active.browseResultsChangedHandler = { [weak self] results, _ in
            let parsed = results.compactMap(Self.parse)
                .filter { $0.expiresAt > Date() }
                .sorted { $0.expiresAt < $1.expiresAt }
            Task { @MainActor in
                guard let self, self.scanID == scanID else { return }
                self.services = parsed
                self.stateText = parsed.isEmpty
                    ? "Waiting for Android pairing broadcast…"
                    : "Found \(parsed.count) station waiting pairing device"
            }
        }
        browser = active
        active.start(queue: queue)
    }

    func stop() {
        // Invalidate before cancel: Network.framework can deliver callbacks after cancellation.
        scanID = nil
        browser?.cancel()
        browser = nil
        services = []
        stateText = "Scanning has stopped"
    }

    func restart() {
        stop()
        start()
    }

    private nonisolated static func parse(_ result: NWBrowser.Result) -> SamsungPairingService? {
        guard case let .bonjour(record) = result.metadata,
              record["v"] == "1",
              let sessionID = record["session"],
              let keyText = record["key"],
              let serverPublicKey = Data(base64URL: keyText),
              serverPublicKey.count == 32,
              let expiresText = record["expires"],
              let expiresMillis = Double(expiresText) else { return nil }
        return SamsungPairingService(
            endpoint: result.endpoint,
            sessionID: sessionID,
            serverPublicKey: serverPublicKey,
            expiresAt: Date(timeIntervalSince1970: expiresMillis / 1_000)
        )
    }
}

@MainActor
final class SamsungPairingRegistrationGate {
    private var activeAgentWrites = 0
    private var pairing = false

    func beginAgentWrite() -> Bool {
        guard !pairing else { return false }
        activeAgentWrites += 1
        return true
    }

    func endAgentWrite() { activeAgentWrites -= 1 }

    func withPairing<T>(_ operation: () async throws -> T) async throws -> T {
        guard !pairing else { throw SamsungPairingClientError.pairingBusy }
        pairing = true
        defer { pairing = false }
        // Wait only for local Agent writes, never for an unrelated Relay request.
        while activeAgentWrites > 0 { try await Task.sleep(nanoseconds: 20_000_000) }
        try Task.checkCancellation()
        return try await operation()
    }
}

enum SamsungPairingRegistrationPolicy {
    static func registration(
        localOnly: Bool,
        vowlanSecret: String,
        notificationForwarding: NotificationForwardingConfig? = nil,
        cloudRegistration: () -> AgentPushRegistration?
    ) throws -> AgentPushRegistration {
        if localOnly {
            return .local(
                vowlanSecret: vowlanSecret,
                notificationForwarding: notificationForwarding
            )
        }
        guard var registration = cloudRegistration(), !registration.localMode else {
            throw SamsungPairingClientError.registrationUnavailable
        }
        registration.vowlanSecret = vowlanSecret
        return registration
    }
}

enum SamsungPairingClient {
    typealias Transport = @Sendable (NWEndpoint, Data, String, String, TimeInterval) async throws -> Data
    static let networkTransport: Transport = { endpoint, body, method, path, timeout in
        try await exchange(endpoint: endpoint, body: body, method: method, path: path, timeout: timeout)
    }
    static let tlsNetworkTransport: Transport = { endpoint, body, method, path, timeout in
        guard case let .hostPort(host, port) = endpoint,
              RemoteDirectHost.isValid("\(host)"),
              let url = URL(string: "https://\(host):\(port.rawValue)\(path)") else {
            throw SamsungPairingClientError.invalidAddress
        }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.httpBody = body
        request.timeoutInterval = timeout
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        // Network.framework performs system trust/hostname validation. This
        // transport neither follows redirects nor retries a TLS failure in HTTP.
        let response = try await WiredHTTPTransport().send(request)
        guard response.body.count <= 65_536 else { throw SamsungPairingClientError.responseTooLarge }
        switch response.statusCode {
        case 200: return response.body
        case 403: throw SamsungPairingClientError.networkNotAllowed
        case 410: throw SamsungPairingClientError.expired
        case 404 where path == "/pair/v1/info": throw SamsungPairingClientError.manualUnsupported
        default: throw SamsungPairingClientError.rejected
        }
    }
    struct ManualResult {
        let message: String
        let route: VoWLANManualRoute
        /// Server clock minus local clock, captured while the pairing window is open.
        let clockOffset: TimeInterval
    }

    private struct SessionInfo: Decodable {
        let product: String
        let version: Int
        let sessionID: String
        let serverPublicKey: String
        let expiresAt: Double
        let serverTime: Double?
        enum CodingKeys: String, CodingKey {
            case product, version
            case sessionID = "session_id", serverPublicKey = "server_public_key", expiresAt = "expires_at"
            case serverTime = "server_time"
        }
    }
    private struct Claim: Encodable {
        let version = 1
        let sessionID: String
        let clientPublicKey: String
        let sealedRegistration: String
        let wantDirectRoute: Bool

        enum CodingKeys: String, CodingKey {
            case version
            case sessionID = "session_id"
            case clientPublicKey = "client_public_key"
            case sealedRegistration = "sealed_registration"
            case wantDirectRoute = "want_direct_route"
        }
    }

    private struct Response: Decodable {
        let configured: Bool
        let deviceIDHint: String?
        let agentID: String?
        let controlPort: UInt16?
        let pcmPort: UInt16?
        let routeProof: String?
        enum CodingKeys: String, CodingKey {
            case configured
            case deviceIDHint = "device_id_hint"
            case agentID = "agent_id"
            case controlPort = "control_port", pcmPort = "pcm_port", routeProof = "route_proof"
        }
    }

    struct PairedDeviceResult {
        let agentID: String
        let message: String
    }
    static func pairDevice(service: SamsungPairingService, code: String,
                           registration: AgentPushRegistration) async throws -> PairedDeviceResult {
        let (response, _) = try await claim(service: service, code: code, registration: registration, direct: false)
        guard let agentID = response.agentID, !agentID.isEmpty else { throw SamsungPairingClientError.directGatewayUnavailable }
        PairedAndroidDeviceStore.allowPairing(agentID)
        return PairedDeviceResult(agentID: agentID,
            message: response.deviceIDHint.map { "Pairing successful (device … \($0) )" } ?? "Pairing successful")
    }
    static func pair(service: SamsungPairingService, code: String, registration: AgentPushRegistration) async throws -> String {
        try await pairDevice(service: service, code: code, registration: registration).message
    }

    static func pairManually(address: SamsungManualPairingAddress, code: String,
                             registration: AgentPushRegistration,
                             transport: Transport? = nil) async throws -> ManualResult {
        let transport = transport ?? (address.usesTLS ? tlsNetworkTransport : networkTransport)
        let data = try await transport(address.endpoint, Data(), "GET", "/pair/v1/info", 8)
        let info: SessionInfo
        do { info = try JSONDecoder().decode(SessionInfo.self, from: data) }
        catch { throw SamsungPairingClientError.manualUnsupported }
        guard info.product == "airsim-pair", info.version == 1, !info.sessionID.isEmpty,
              info.sessionID.count <= 128, let publicKey = Data(base64URL: info.serverPublicKey), publicKey.count == 32,
              info.expiresAt.isFinite else { throw SamsungPairingClientError.manualUnsupported }
        let service = SamsungPairingService(endpoint: address.endpoint, sessionID: info.sessionID,
            serverPublicKey: publicKey, expiresAt: Date(timeIntervalSince1970: info.expiresAt / 1_000))
        let (response, clientKey) = try await claim(service: service, code: code, registration: registration, direct: true, transport: transport)
        guard let agentID = response.agentID, !agentID.isEmpty,
              let controlPort = response.controlPort, let pcmPort = response.pcmPort,
              let proof = response.routeProof, let encodedSecret = registration.vowlanSecret,
              let secret = Data(base64URL: encodedSecret),
              SamsungDirectRouteProof.verify(proof, secret: secret, sessionID: service.sessionID,
                clientKey: clientKey, agentID: agentID, controlPort: controlPort, pcmPort: pcmPort) else {
            throw SamsungPairingClientError.directGatewayUnavailable
        }
        // Verify the Android's signed *internal* ports above, then use the
        // explicit external port mapping supplied by the gateway owner. Never
        // persist Android's private ports as public endpoints by accident.
        let route = VoWLANManualRoute(agentID: agentID, host: address.host,
            controlPort: address.remoteControlPort ?? controlPort,
            pcmPort: address.remotePCMPort ?? pcmPort, tls: address.usesTLS ? true : nil)
        guard route.endpoint != nil else { throw SamsungPairingClientError.directGatewayUnavailable }
        // Server clock lets the signer avoid 401 when the phone and the paired
        // Android are not time-synchronised (common across Tailscale carriers).
        let clockOffset = info.serverTime.map { $0 / 1_000 - Date().timeIntervalSince1970 } ?? 0
        // Do not persist an unverified server response or silently trust an old port.
        PairedAndroidDeviceStore.allowPairing(agentID)
        return ManualResult(message: "Encrypted pairing successful, verifying direct connection to Calls gateway...", route: route,
                            clockOffset: clockOffset)
    }

    private static func claim(service: SamsungPairingService, code: String,
                              registration: AgentPushRegistration, direct: Bool,
                              transport: Transport = networkTransport) async throws -> (Response, String) {
        guard code.range(of: #"^[0-9]{6}$"#, options: .regularExpression) != nil else {
            throw SamsungPairingClientError.invalidCode
        }
        guard service.expiresAt > Date() else { throw SamsungPairingClientError.expired }
        let registrationData = try JSONEncoder().encode(registration)
        let sealed = try SamsungPairingCrypto.seal(
            registration: registrationData,
            serverPublicKey: service.serverPublicKey,
            sessionID: service.sessionID,
            code: code
        )
        let body = try JSONEncoder().encode(Claim(
            sessionID: service.sessionID,
            clientPublicKey: sealed.clientPublicKey.base64URL,
            sealedRegistration: sealed.combined.base64URL,
            wantDirectRoute: direct
        ))
        let responseData = try await transport(service.endpoint, body, "POST", "/pair/v1/claim", 25)
        let response = try JSONDecoder().decode(Response.self, from: responseData)
        guard response.configured else { throw SamsungPairingClientError.rejected }
        return (response, sealed.clientPublicKey.base64URL)
    }

    private static func exchange(endpoint: NWEndpoint, body: Data, method: String = "POST",
                                  path: String = "/pair/v1/claim", timeout: TimeInterval = 25) async throws -> Data {
        let cancellation = PairingExchangeCancellation()
        return try await withTaskCancellationHandler {
          try await withCheckedThrowingContinuation { continuation in
            let connection = NWConnection(to: endpoint, using: .tcp)
            let state = PairingExchangeState(connection: connection, continuation: continuation)
            guard cancellation.install(state) else { return }
            connection.stateUpdateHandler = { newState in
                switch newState {
                case .ready: state.send(body: body, method: method, path: path)
                case .failed(let error): state.finish(.failure(error))
                case .cancelled: state.finish(.failure(SamsungPairingClientError.connectionClosed))
                default: break
                }
            }
            connection.start(queue: DispatchQueue(label: "com.simhelp.samsung-pair.claim"))
            DispatchQueue.global().asyncAfter(deadline: .now() + timeout) { [weak state] in
                state?.finish(.failure(SamsungPairingClientError.timedOut))
            }
          }
        } onCancel: { cancellation.cancel() }
    }
}

private final class PairingExchangeCancellation: @unchecked Sendable {
    private let lock = NSLock()
    private var state: PairingExchangeState?
    private var cancelled = false
    func install(_ state: PairingExchangeState) -> Bool {
        lock.lock()
        let wasCancelled = cancelled
        if !wasCancelled { self.state = state }
        lock.unlock()
        if wasCancelled { state.finish(.failure(CancellationError())) }
        return !wasCancelled
    }
    func cancel() {
        lock.lock()
        cancelled = true
        let active = state
        lock.unlock()
        active?.finish(.failure(CancellationError()))
    }
}

@MainActor
enum SamsungPairingCompletionCoordinator {
    static func complete(
        performPairing: () async throws -> String,
        refreshVoWLAN: () async -> Void
    ) async rethrows -> String {
        let message = try await performPairing()
        await refreshVoWLAN()
        return message
    }
}

private final class PairingExchangeState: @unchecked Sendable {
    private let connection: NWConnection
    private let continuation: CheckedContinuation<Data, Error>
    private var received = Data()
    private var finished = false
    private let lock = NSLock()
    private var metadata = false

    init(connection: NWConnection, continuation: CheckedContinuation<Data, Error>) {
        self.connection = connection
        self.continuation = continuation
    }

    func send(body: Data, method: String, path: String) {
        metadata = method == "GET" && path == "/pair/v1/info"
        var request = Data("\(method) \(path) HTTP/1.1\r\nHost: airsim-pair.local\r\nContent-Type: application/json\r\nContent-Length: \(body.count)\r\nConnection: close\r\n\r\n".utf8)
        request.append(body)
        connection.send(content: request, completion: .contentProcessed { [weak self] error in
            if let error { self?.finish(.failure(error)); return }
            self?.receive()
        })
    }

    private func receive() {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { [weak self] content, _, isComplete, error in
            guard let self else { return }
            if let content { self.received.append(content) }
            if let error { self.finish(.failure(error)); return }
            if self.received.count > 65_536 { self.finish(.failure(SamsungPairingClientError.responseTooLarge)); return }
            if isComplete { self.finish(self.parseResponse()); return }
            self.receive()
        }
    }

    private func parseResponse() -> Result<Data, Error> {
        Result { try SamsungPairingHTTPResponse.decode(received, metadata: metadata) }
    }

    func finish(_ result: Result<Data, Error>) {
        lock.lock()
        guard !finished else { lock.unlock(); return }
        finished = true
        lock.unlock()
        connection.stateUpdateHandler = nil
        connection.cancel()
        continuation.resume(with: result)
    }
}

enum SamsungPairingHTTPResponse {
    static func decode(_ received: Data, metadata: Bool) throws -> Data {
        guard received.count <= 65_536,
              let range = received.range(of: Data("\r\n\r\n".utf8)), range.lowerBound <= 8_192,
              let header = String(data: received[..<range.lowerBound], encoding: .utf8) else {
            throw SamsungPairingClientError.rejected
        }
        let lines = header.components(separatedBy: "\r\n")
        let status = lines[0].split(separator: " ")
        guard status.count >= 2, status[0] == "HTTP/1.1" || status[0] == "HTTP/1.0" else {
            throw SamsungPairingClientError.rejected
        }
        guard status[1] == "200" else {
            if status[1] == "403" { throw SamsungPairingClientError.networkNotAllowed }
            if status[1] == "410" { throw SamsungPairingClientError.expired }
            if status[1] == "404", metadata { throw SamsungPairingClientError.manualUnsupported }
            throw SamsungPairingClientError.rejected
        }
        let lengths = lines.dropFirst().filter { $0.lowercased().hasPrefix("content-length:") }
        let body = Data(received[range.upperBound...])
        guard lengths.count == 1,
              let length = Int(lengths[0].dropFirst(15).trimmingCharacters(in: .whitespaces)),
              length == body.count,
              !lines.dropFirst().contains(where: { $0.lowercased().hasPrefix("transfer-encoding:") }) else {
            throw SamsungPairingClientError.rejected
        }
        return body
    }
}

enum SamsungPairingClientError: LocalizedError, Equatable {
    case invalidCode, expired, rejected, responseTooLarge, connectionClosed, registrationUnavailable, pairingBusy, invalidAddress
    case manualUnsupported, directGatewayUnavailable, timedOut, networkNotAllowed
    var errorDescription: String? {
        switch self {
        case .invalidCode: return "Please enter the 6-digit verification code on your Samsung screen"
        case .expired: return "Samsung pairing window has expired, please start again"
        case .rejected: return "Samsung rejected the pairing, please check the verification code and try again."
        case .networkNotAllowed: return "Android rejects the current network source and the verification code has not yet been verified. Please update the Android App and confirm that both ends are on the same Wi-Fi/hotspot or a Tailscale network that allows mutual access."
        case .responseTooLarge: return "The data returned by Samsung is abnormal"
        case .connectionClosed: return "LAN connection to Samsung has been lost"
        case .registrationUnavailable: return "Relay/push configuration is not ready. Please complete the cloud configuration in the settings first; if you only need a local connection, please turn on 'Local Mode Pairing'."
        case .pairingBusy: return "Another pairing is in progress, please try again later"
        case .invalidAddress: return "Please fill in the private IPv4 or HTTPS domain name according to your choice, and the port 1–65535; the domain name does not include the protocol, path, or IP address."
        case .manualUnsupported: return "No SimHelp pairing information was returned for this address. Please update the Android App and fill in the current one-time pairing port, not the ADB, Relay or call port."
        case .directGatewayUnavailable: return "Pairing has been written, but the direct call gateway is not ready or authentication failed. Please check the Android default phone role and PCM bridge, then open a new pairing window and try again."
        case .timedOut: return "Connection timed out. Please check the IP, Current paired port, LAN isolation or Tailscale connection and access rules at both ends."
        }
    }
}

private extension Data {
    init?(base64URL: String) {
        var value = base64URL.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        value += String(repeating: "=", count: (4 - value.count % 4) % 4)
        self.init(base64Encoded: value)
    }

    var base64URL: String {
        base64EncodedString().replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
    }
}
