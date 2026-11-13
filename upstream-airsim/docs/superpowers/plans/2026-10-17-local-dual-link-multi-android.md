# Local Dual-Link and Multi-Android Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 同一 iOS AirSIM 同时连接多台安卓，支持本地 VoWLAN＋VoBLE 双待、指定设备拨出、按来电来源接听，以及通话中其他设备来电只提醒。

**Architecture:** 共享发现入口管理多个隔离的设备会话；设备协调层统一已认证的 VoWLAN／BLE 身份，通话注册表与唯一媒体租约独立于默认拨号选择。沿用现有 Android Telecom、加密控制与 PCM 协议，不做通话途中跨传输迁移；按来源设备锁定所有命令。

**Tech Stack:** Swift／SwiftUI／Combine、CoreBluetooth、Network、CallKit、UserNotifications、ActivityKit；现有 Java Android Bridge；XCTest、JVM／真实本地 TCP 测试。最低 iOS 16.3，Android API 29，targetSdk 35，不引入第三方依赖。

**Spec:** `docs/superpowers/specs/2026-10-17-local-dual-link-multi-android-design.md`（用户回复“开始”批准设计，并回复“执行”选择推荐的 Native 方式）。

## Global Constraints

- 保留单 VoWLAN、单蓝牙、云端、自动模式，新增“本地双通道”；默认偏好不静默改变。
- 多安卓是真正同时连接／待机，验收至少两台，不以保存配对列表代替连接。
- 指定设备离线不借另一台拨出；接听／拒接／挂断只操作来源设备。
- A 通话时 B 只提醒，不中断 A，不自动接听、拒接、挂断或为 B 启动 PCM／降音量。
- 一次只持有一路音频。通话途中保持设备及传输锁定；不暗中重拨或迁移链路。
- 双通道不强制 Relay／PushKit、不增加 Relay 轮询；CallKit 本机集成与云端开关分离。
- 保留 HMAC、nonce、时间戳、BLE 认证／加密与重放窗口；恢复连接不等于恢复认证在线。
- 保留旧凭据、短信与设备记录；不清除用户数据，不因新配对覆盖别台使用的密钥。
- 不回退已修复的配对 IPv6、短信导航、蓝牙 UI 卡顿及三星最低音量策略。
- 所有旧工作树改动保留；本轮不提交／push／发布／生产部署。设备安装另取得明确授权，不能把之前 bugfix 的安装许可沿用到本功能。

## Review Focus

1. A、B 的 callID／号码相同：必须隔离；双传输上报同一台同一通电话却必须去重（Task 1、4）。
2. 默认拨号设备变化、B 断线、A 迟到异步回复：不能改写正在通话设备或释放另一台音频（Task 1、2、4）。
3. iOS 恢复多外设、系统蓝牙开关、取消一台配对：不能只恢复第一个、卡主线程或取消所有设备（Task 2、6）。
4. 旧全局 VoWLAN 凭据、新配对尚在进行、手动地址更换：不能借用别台密钥或把 HTTP 200 当认证成功（Task 3）。
5. 后台 B 来电／通知点击／云端真实 VoIP Push：不能覆盖 A 的 CallKit／灵动岛，也不能漏掉必须完成的 PushKit 上报（Task 4、5、6）。

## 文件结构与责任

| 文件 | 责任 |
| --- | --- |
| 新增 `iOS/AirSIM/DeviceCallRegistry.swift` | 设备域通话键、事件去重、终态与主通话／提醒策略，不操作网络或 UIKit |
| 新增 `iOS/AirSIM/VoBLERadioController.swift` | 唯一 CBCentralManager、扫描、外设回调分发和系统多外设恢复 |
| 新增 `iOS/AirSIM/VoBLEDeviceHub.swift` | 每台 BLE 控制／通话／媒体会话的生命周期与已认证目录 |
| 修改 `iOS/AirSIM/VoBLECentralController.swift` | 保留为单外设认证控制会话，移出全局扫描／默认设备的所有权 |
| 新增 `iOS/AirSIM/LocalDeviceDirectory.swift` | 多设备路由与认证能力汇合、设备级 VoWLAN 会话及本地事件订阅 |
| 修改 `iOS/AirSIM/VoWLANAuth.swift`、`SamsungPairingClient.swift`、`SamsungPairingView.swift`、`VoWLANController.swift` | 设备级凭据、配对事务、共享发现及旧安装兼容 |
| 新增 `iOS/AirSIM/DeviceCallActionRouter.swift` | 绑定来源设备／传输／系统 UUID 的不可漂移操作与唯一媒体租约 |
| 新增 `iOS/AirSIM/OtherDeviceCallReminder.swift` | 次要来电提示的去重、撤销和来源明确的本地通知 |
| 修改 `iOS/AirSIM/AppModel.swift`、`CallKitController.swift`、`VoBLECallCoordinator.swift` | 替换单全局来源假设；接入注册表、动作路由及媒体授权 |
| 修改 `iOS/AirSIM/ConnectionModePreference.swift`、`VoBLEModeController.swift`、`AirSIMSetupView.swift`、`PhoneViews.swift`、`VoBLEPairingView.swift` | 新模式、拨号设备选择、各设备状态与配对操作目标 |
| 修改 `iOS/AirSIM/BackgroundStandbyController.swift`、`LiveActivityController.swift`、`RootView.swift`、`WatchCallCoordinator.swift`、`iOS/Shared/WatchCallPayload.swift`、`iOS/Shared/AirSIMLiveActivityShared.swift` | 次要提醒、深链与现有主通话展示／Watch 动作的来源保护；不新增 Watch 直连功能 |
| 新增设备域 XCTest 文件，修改 `iOS/AirSIMTests/AirSIMTests.swift` 及 `iOS/AirSIM.xcodeproj/project.pbxproj` | 各单元和生产者／消费者集成回归，所有新文件必须入 target |

命名是计划接口约定，不是已有实现。Task 1–3 先通过适配器保留现有单机功能，Task 4 连接完整多机行为，Task 5 开放模式入口；不得在中间任务把未完成能力标成在线。

## 验证命令约定

由 `xcrun simctl list devices booted` 选定已启动的测试模拟器，将实际 ID 填入 `SIM_ID`，不能误用物理 Air UDID；测试不使用生产 Bundle 配置。每阶段先运行新增测试观察失败，再运行整个 iOS 测试 target；不要把编译成功或 0 个测试视为通过。

```sh
xcodebuild -project iOS/AirSIM.xcodeproj -scheme AirSIM \
  -destination "platform=iOS Simulator,id=$SIM_ID" \
  -derivedDataPath /tmp/AirSIM-multi-device-tests -jobs 2 \
  CODE_SIGNING_ALLOWED=NO test
```

新增测试首轮可加 `-only-testing:AirSIMTests/<TestClass>`，最终必须去掉过滤执行全套。采用带可控响应的真实本地 TCP／认证夹具；仅 CoreBluetooth 和系统通知送达边界需要替身，不 mock 注册表或动作路由本身。

---

### Task 1: 设备域通话注册表与唯一所有者

**Files:** Create `iOS/AirSIM/DeviceCallRegistry.swift`, `iOS/AirSIMTests/DeviceCallRegistryTests.swift`; modify `iOS/AirSIM/AppModel.swift`, `iOS/AirSIM.xcodeproj/project.pbxproj`.

**Interfaces:**
- Produces `DeviceCallKey: Hashable, Sendable { agentID: String, callID: String, generation: UInt64 }`。
- Produces `DeviceCallEvent: Sendable { agentID: String, callID: String, replacesCallID: String?, state: CallLifecycleState, transport: CallTransport, transportEpoch: UInt64, backendGeneration: UInt64?, number: String?, direction: String }`。
- Produces `DeviceCallEffect` cases `present(DeviceCallKey)`, `remind(DeviceCallKey)`, `update(DeviceCallKey)`, `dismiss(DeviceCallKey)`, `ended(DeviceCallKey)`。
- Produces `DeviceCallRegistry.apply(_ event: DeviceCallEvent) -> [DeviceCallEffect]`, `activate(_ key: DeviceCallKey) -> Bool`, `finish(_ key: DeviceCallKey)`, `latestEvent(for key: DeviceCallKey) -> DeviceCallEvent?`，read-only `active: DeviceCallKey?`, `ringing: [DeviceCallKey]`。
- Registry 生成统一通话 generation；BLE／VoWLAN transportEpoch 是独立输入，不能相互比较大小来决定谁是新通话。alias 只接受同设备已认证操作对应的 provisional→权威 ID，不按号码或时间猜测。

- [ ] **Step 1:** 写 `testSameRawCallIDOnTwoAgentsDoesNotCollide`（A active 后 B ringing 得到 B remind，active 仍 A）；`testTwoTransportsForSameBackendCallRemindOnce`（不同 transportEpoch 不生成第二提醒）；`testEndedTombstoneRejectsLateRinging`；`testProvisionalAliasCannotAdoptAnotherAgentsCall`。
- [ ] **Step 2:** 注册源文件及测试 target，按约定命令仅运行 `DeviceCallRegistryTests`，确认缺少行为导致失败。
- [ ] **Step 3:** 实现上述纯状态机；终态防回流和同一键处理必须幂等。将 AppModel 现有单机来电／结束入口先包装成有已认证 agentID 的事件；现有用户拨出／接听意图调用 activate，失败／结束调用 finish，不因收到安卓本机 active 就取得远程所有权。保留原展示适配器，不引入新连接。
- [ ] **Step 4:** 增加消费者测试 `testLegacyIngressDoesNotEndAnotherSourceOnLateResult`，从 AppModel 的实际入口注入 A／迟到 B，不只测新 helper。
- [ ] **Step 5:** 运行新增及整个 iOS suite；检查 diff，暂不 commit，记录可独立评审的变更范围。

### Task 2: 一个蓝牙 Radio，多台隔离会话

**Files:** Create `iOS/AirSIM/VoBLERadioController.swift`, `iOS/AirSIM/VoBLEDeviceHub.swift`, `iOS/AirSIMTests/VoBLEMultiDeviceTests.swift`; modify `VoBLECentralController.swift`, `VoBLECallCoordinator.swift`, `VoBLEPairingView.swift`, `AppModel.swift`, project target entries.

**Interfaces:**
- Consumes Task 1 的 `DeviceCallEvent` 与注册表。
- Produces `@MainActor VoBLERadioController`，`start()`, `stop()`, `connect(peripheralID: UUID)`, `cancel(peripheralID: UUID)`；published `discoveredPeers: [VoBLEDiscoveredPeer]`。单个 CBCentralManager 保留现有 restoration identifier。
- 单外设 `VoBLECentralController` 经 `init(radio: VoBLERadioController, peripheralID: UUID, pairingStore: any VoBLEPairingStoring)` 使用共享 Radio；其现有 `send(...)`、认证和媒体 writer API 保持可适配。取消一个会话不能调用共享 stopScan／取消其他会话。
- Produces `@MainActor VoBLEDeviceHub`，`start()`, `stop(except agentID: String?)`, `session(for agentID: String) -> VoBLECentralController?`, `forget(agentID: String) async throws`，以及 `onCallEvent: ((DeviceCallEvent) -> Void)?`。目录仅按认证身份建键，认证前用外设 ID 临时槽位，不以缓存外设 UUID 直接判定已配对在线。
- 默认拨号会话通过独立选择适配现有单机入口；未选中的设备保持连接／事件接收，但状态不能覆盖默认会话或当前通话。

- [ ] **Step 1:** 写 `testTwoAuthenticatedSessionsStayConnectedWhenDefaultChanges`、`testDisconnectBDoesNotFailAPendingCommand`、`testRevokeBDoesNotStopSharedScanOrDisconnectA`、`testRestoreAdoptsEveryEligibleOSPeripheralAndRequiresFreshAuth`，以具体两个外设身份及分别回应的蓝牙边界替身驱动真实 Hub／session。
- [ ] **Step 2:** 仅运行 `VoBLEMultiDeviceTests`，观察原单外设假设导致失败。
- [ ] **Step 3:** 把扫描、恢复和中央回调分发移入 Radio，按 peripheralID 路由到相应会话；每台保留独立分片、重放窗口、命令和取消代次。已知设备依次握手，握手完成的控制会话并行待机；陌生设备只有用户选择后进入一次性配对，不自动连续弹码。
- [ ] **Step 4:** Hub 为每台保留 VoBLECallCoordinator，但媒体引擎延迟启动；增加 `mediaPermission: (VoBLECallIdentity) -> Bool` 授权入口，未获 Task 1 active 所有权时不能因收到 `active` 就启动媒体。默认会话旧功能由同一代码适配，不保留两套 BLE 控制实现。
- [ ] **Step 5:** 增加 `testPairingWorkAndCredentialIOStayOffMainThreadForBothPeers`、`testBluetoothToggleDoesNotRestoreOnlyFirstPeer`、`testStandbyPeersNeverRequestPCM`；运行完整 iOS suite，保留现有 3 秒、同一 callID/generation 的短断链恢复策略。

### Task 3: 多设备 VoWLAN 凭据、认证路由与事件订阅

**Files:** Create `iOS/AirSIM/LocalDeviceDirectory.swift`, `iOS/AirSIMTests/LocalDeviceDirectoryTests.swift`; modify `VoWLANAuth.swift`, `VoWLANController.swift`, `SamsungPairingClient.swift`, `SamsungPairingView.swift`, `AppModel.swift`, project entries.

**Interfaces:**
- Produces `LocalDeviceRoutes { agentID: String, vowlan: VoWLANEndpoint?, bluetoothReady: Bool }`，其中 vowlan 只能表示已认证端点，不承载凭据明文展示。
- Produces `@MainActor LocalDeviceDirectory`，`routes(for agentID: String) -> LocalDeviceRoutes?`, `api(for agentID: String) -> AirSIMAPI?`, `verify(agentID: String, endpoint: VoWLANEndpoint) async throws`, `forget(agentID: String) async throws`，`onCallEvent: ((DeviceCallEvent) -> Void)?`；消费 Task 2 的已认证 BLE 目录，不重建 CBCentralManager。
- Produces `VoWLANCredentialStore.load(agentID: String) -> VoWLANCredential?`, `save(_ credential: VoWLANCredential, agentID: String) throws`, `remove(agentID: String)`；保留旧无参 API 供尚未迁移的旧单机调用，所有新多机路由必须显式指定 agentID。
- 配对事务生成临时 credential，不替换正在使用的全局密钥。成功 claim 后，经该密钥的 HMAC 健康检查确认来源 agentID 才提交关联；取消或失败不影响旧关联。Bonjour claim 可继续使用链路本地 IPv6，控制端点仍用现有 IPv4 广播／手动路由，不能因想获取端口证明而卡在不存在的 IPv6 PCM 路由。

- [ ] **Step 1:** 写 `testPairingBDoesNotOverwriteACredentialOrRoute`、`testWrongHealthIdentityCannotJoinTwoTransports`、`testLegacyCredentialMigratesOnlyAfterAuthenticatedBinding`、`testHTTP200WithoutHMACNeverMakesDeviceReady`。
- [ ] **Step 2:** 用受控双 TCP Agent 夹具运行 `LocalDeviceDirectoryTests` 并确认失败；沿用真实 HMAC 计算／nonce 校验，不 mock 认证结论。
- [ ] **Step 3:** 将 VoWLAN 共享发现与“当前默认设备的 availability”分开；为每个已认证设备保留独立 API、验证代次和事件 revision。Task 2 BLE 身份与 VoWLAN 身份相同才合并能力，设备名称与号码不是身份键。
- [ ] **Step 4:** 为已认证、获准连接的设备订阅现有 `waitForCallEvent(after:timeout:)`，每设备至多一个在途长轮询，timeout 25 秒；旧端不支持时复用现有本地轮询退避策略。所有任务绑定设备／端点代次，忘记设备立即取消。不得把该任务派到 Relay，也不得在 App 挂起时承诺持续执行。
- [ ] **Step 5:** 测试 `testDefaultDialBindingDoesNotFilterBIncomingEvents`、`testEndpointReplacementDropsOldPollResponse`、`testManualRouteAndBonjourMergeKeepTheVerifiedAgent`、`testDeletedDeviceCannotReappearFromSavedRoute`；运行 iOS suite，并运行 Android Standalone suite 保护手动／自动配对与网关认证。

### Task 4: 来源锁定的通话动作、CallKit 与唯一媒体租约

**Files:** Create `iOS/AirSIM/DeviceCallActionRouter.swift`, `iOS/AirSIMTests/DeviceCallActionRouterTests.swift`; modify `AppModel.swift`, `CallKitController.swift`, `VoBLECallCoordinator.swift`, `CallLifecycleStore.swift`, `WatchCallCoordinator.swift`, `iOS/Shared/WatchCallPayload.swift`, project entries.

**Interfaces:**
- Consumes `DeviceCallKey`, `DeviceCallRegistry`, Task 2 Hub 与 Task 3 Directory。
- Produces `LockedDeviceCallRoute { key: DeviceCallKey, transport: CallTransport, systemUUID: UUID }`。
- Produces `@MainActor DeviceCallActionRouter`：`dial(agentID: String, number: String, mode: AirSIMConnectionMode) async throws -> LockedDeviceCallRoute`, `answer(_ key: DeviceCallKey) async throws`, `end(_ key: DeviceCallKey, rejectIfRinging: Bool) async throws`, `sendDTMF(_ digits: String, for key: DeviceCallKey) async throws`；内部对每次拨出保留目标快照，不通过当前 UI 选择重新解析。
- Produces `DeviceMediaLease.acquire(_ key: DeviceCallKey) -> Bool`, `release(_ key: DeviceCallKey)`；不同键的 release 必须无副作用。
- CallKit delegate 到 handler 的 answer／end／mute／DTMF 路径必须传入 action.callUUID，并由明确的 UUID→LockedDeviceCallRoute 映射解析；旧调用可适配，但不能在映射缺失时借用全局 currentCall。Watch 动作同样校验 UUID／agentID；缺少来源的旧负载只允许匹配唯一当前通话。

- [ ] **Step 1:** 写 `testSelectingBAfterADialDoesNotMoveLateDialResult`、`testBHangupAndDisconnectCannotReleaseAMedia`、`testCallKitActionForBDoesNotHangupCurrentA`、`testOfflineSelectedDeviceNeverDialsAnotherReadyDevice`。
- [ ] **Step 2:** 运行 `DeviceCallActionRouterTests`，必须经真实 Router 调用带精确参数检查的传输边界，不只断言一个模拟组件存在。
- [ ] **Step 3:** 接入所有本地拨出、来电、接听和终态入口；AppModel 对 active/present 效果更新主通话，对 remind 效果保持 A 不变。接听 B 遇到 A 活动时返回明确 busy，仅提示，不发送结束 A 或接听 B 的命令。
- [ ] **Step 4:** 媒体准备／最低音量接管只在租约持有者被明确拨出或接听后执行。安卓本机接听 B 后即使发布 active，也不能由 iOS 擅自创建 B 的远程 PCM 租约。当前传输失效只走原路径恢复／结束逻辑，不在通话中改走备用路径。
- [ ] **Step 5:** 测试 `testWLANAndBLEIncomingForSameDeviceYieldSingleSystemCall`、`testRawCallIDCollisionOnTwoPhonesKeepsSeparateUUIDs`、`testIdleIncomingSelectionChangesSystemPresentationWithoutRejectingOtherAndroid`、`testCloudPushReportFailureDoesNotEndLocalA`；运行完整 iOS、Android 控制及 PCM 回归。

### Task 5: 本地双通道入口、设备状态与次要来电提醒

**Files:** Create `iOS/AirSIM/OtherDeviceCallReminder.swift`, `iOS/AirSIMTests/OtherDeviceCallReminderTests.swift`; modify `ConnectionModePreference.swift`, `VoBLEModeController.swift`, `AirSIMSetupView.swift`, `PhoneViews.swift`, `VoBLEPairingView.swift`, `BackgroundStandbyController.swift`, `RootView.swift`, `LiveActivityController.swift`, `iOS/Shared/AirSIMLiveActivityShared.swift`, project entries.

**Interfaces:**
- `AirSIMConnectionMode.localDual` 的持久化值为 `localDual`、标题“本地双通道”；startsVoWLAN=true、startsBluetooth=true、startsCloud=false、usesCallKit=true。`DialRouteSelector.preferred(...)` 对这一个设备仅 VoWLAN→BLE，不使用云端。
- Produces `OtherDeviceCallReminder { key: DeviceCallKey, deviceName: String, number: String?, stillRinging: Bool }` 与 `@MainActor OtherDeviceCallReminderController`：`init(lookup: @escaping (DeviceCallKey) -> OtherDeviceCallReminder?)`、`consume(_ effects: [DeviceCallEffect])`；published `reminders: [OtherDeviceCallReminder]`。lookup 使用注册表 latestEvent 和目录的当前认证设备资料，只有仍响铃且非主通话才返回提醒；发通知前再次验证。通知 ID 从整个设备域通话键稳定派生，不包含号码。
- `AppModel.otherDeviceCallReminders` 提供真实状态；通知 userInfo 的新事件 `other_android_incoming` 携带 agentID／callID／协调层 generation。点击只打开并验证提醒来源，不自动接听，也不改变默认拨号设备。

- [ ] **Step 1:** 写 `testLocalDualStartsBothLocalTransportsWithoutCloudOrPushKit`、`testLocalDualRouteStaysInsideSelectedAgent`、`testLegacyFourModePreferencesKeepTheirMeaning`；先运行并观察新模式行为缺失。
- [ ] **Step 2:** 接入新模式及运行策略，覆盖所有 `.bluetooth`／`.vowlan` 特判、模式 switch、`LocalModePreference`／`CloudModePreference` 旧布尔调用；是否访问 Relay／PushKit 一律归 startsCloud，不能借 usesCallKit 推断云端开启。避免新模式在线却禁用拨号／CallKit。开始配对入口可分别添加 Wi-Fi 与 BLE，两者独立，不要求用户先完成另一种配对；同一设备两种认证完成后才显示双链路就绪。
- [ ] **Step 3:** 拨号设备列表显示每台真实的两种本地状态，选择只影响下一次拨出；原设备删除／忘记语义保持。首次设置页五种模式改用系统 menu Picker，避免五个长标题挤在 segmented 控件；不重做整套视觉设计。
- [ ] **Step 4:** 写并实现 `testBReminderNeverReplacesACallOrActivityTimer`、`testDuplicateRingingCreatesOneNotification`、`testBEndedRemovesOnlyBReminder`、`testAEndsRevalidatesBInsteadOfAutoAnswer`。前台给来源明确提示和一次轻触；后台用无通话混音的本地通知，服从系统授权，权限拒绝不阻断主通话。
- [ ] **Step 5:** CallKit／灵动岛继续显示主通话 A；B 在其他设备提醒集合中，不重置 A startedAt。B 已结束时撤销通知，晚到响铃不能复活。忙时通知操作不会隐式“结束 A 并接听 B”；已有真正 VoIP Push 仍执行必须的 CallKit 上报及 completion，不伪装成本地通知。
- [ ] **Step 6:** 运行全部 iOS suite，保留真实 hosted SwiftUI 短信导航回归，并为提醒的生产事件入口和通知点击处理各加一条消费者测试，不能仅测试通知替身。

### Task 6: 全量回归、兼容与真机验收准备

**Files:** Modify `iOS/README.md`, `docs/voble-real-device-test-matrix.md`, `docs/superpowers/specs/2026-10-17-local-dual-link-multi-android-design.md`；仅在实际改变共享 Android 协议时才同步安卓组件 README 和协议测试，不能未经需要增改 Relay。

**Interfaces:** 消费 Task 1–5 的真实 AppModel、Hub、Directory、Router 和提醒控制器；不在测试中另写一个能通过的独立路由实现。

- [ ] **Step 1:** 用完整生产协调链覆盖至少两设备的“连接→指定 A 拨出→B 来电提醒→B 结束→A 挂断→下一通选 B”；断言真实发出的命令目标、媒体启动次数为一路、A 的计时未被 B 重置。
- [ ] **Step 2:** 增加锁屏／恢复状态夹具：恢复两个 OS peripheral、删除其中一个、同一设备换地址、旧认证结果迟到、任务取消、权限撤回。断言没有用历史号码补齐当前不可读号码、没有主线程认证／持续扫描刷 UI。
- [ ] **Step 3:** 运行完整 iOS XCTest、`sh android-standalone/test.sh`、`sh android/phone-control-app/test.sh`、两种 APK 构建／验签、iOS Release 无签名完整归档及 `sh iOS/scripts/test-package-unsigned.sh`。有基础设施失败时保留诊断并报告，不能用“构建通过”替代没跑的测试。
- [ ] **Step 4:** 请求本功能的保留数据安装许可，并确认 iPhone、两台安卓的身份与当前连接地址。安装后实测两台同时连接、指定拨出、来电来源、A 通话中 B 提醒、B 未结束／已结束、Wi-Fi／蓝牙独立断开及下一通备用链路、锁屏恢复、双向语音与三星音量；不自行拨打真实号码、发短信或删除真实设备。
- [ ] **Step 5:** 在测试矩阵逐项记录自动化／真实反馈／未执行；最终新鲜命令验证、整段独立代码审查并处理重要问题后再交付。仅确认实施不等于授权 commit／push／Release／TestFlight，交付明确列出尚未授权的动作。

## 计划自查

- 设计第 1–3 节分别由 Task 1／4 的归属与 Task 5 的模式／提醒实现；第 4 节连接／凭据由 Task 2／3 实现；第 5 节后台／系统约束由 Task 4／5 实现；迁移与验收由 Task 3／6 实现。
- Review Focus 的五类故障均有具名测试归属。设备会话、传输代次、统一通话代次、系统 UUID 与媒体租约不是同一个状态字段。
- 没有跨通话／跨安卓自动重拨，没有把“多设备连接”缩成“多设备配对缓存”，没有新增 Relay 请求定时器。
- 整个计划应作为一个接口紧密关联的项目顺序实施；每个任务有独立可测交付点，不在任务间推送未完成版本。

## Execution Handoff

用户已回复“执行”，按推荐的 **Native** 方式实施：同一执行者顺序实现与验证，最后独立审查整段改动。进度与证据记录在本计划专属 ledger；安装、提交与发布仍需另行授权。
