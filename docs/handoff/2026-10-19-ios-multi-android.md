# AirSIM Handoff：iOS 多安卓配对修复

交接日期：2026-10-19（Asia/Shanghai）。本文是本地工作区快照，不是发布或真机验收回执。

## 1. 接手结论

本轮针对 iOS 多安卓配对审查的三项问题已完成代码修复，并补齐 6 项回归测试。模拟器 `build-for-testing` 成功，全量 **276 项 XCTest、0 失败，测试命令退出 0**。独立只读复核未发现剩余的本轮阻塞问题。

**源码改动尚未提交、推送或发布。** 初版交接时未安装；交接后已按用户追加授权保留数据覆盖安装 iPhone Air，最新回执见第 8 节。本轮没有修改 Android、AVF 或 Relay，没有进行真实电话／短信操作，也没有完成两台安卓同时连接的真机验收。

第 8 节的启动检查已完成。当前最合适的下一步：在用户确认第二台安卓与操作授权后进行双安卓验收；通过后再按新的明确授权提交／发布。

后续新增的云端拨号卡片与蓝牙配对状态修复及最新覆盖安装见第 9 节；第 8 节首次安装的包不包含这些更晚的源码变化，现已被第 9 节包覆盖。

## 2. 工作区与版本

| 项目 | 快照 |
| --- | --- |
| 实际修改的 checkout | `/Users/kyle/.codex/worktrees/voble/AirSIM` |
| 分支 | `VoBLE` |
| 当前 HEAD | `9e2f80faaeb617d4e5c097972c190ff42c88bab5` |
| 会话显示的项目目录 | `/Users/kyle/codex project/AirSIM`，不要直接假定它包含本轮改动 |
| 仓库发布基线记录 | Apps `v0.9.8.1`；Android `0.9.8.1 (95)`；iOS／Watch／Live Activity `0.9.8 (95)` |
| 本轮版本号 | 未变更；已发布 build 95 不包含这批未提交修复 |

版本和既往上传事实见 [0.9.8.1 发布记录](../releases/0.9.8.1.md)。该记录记载 Xcode 上传成功后 Apple 仍在处理；不能据此宣称当前已通过外测审核。接手时如需发布，重新查询真实状态。

开始操作前执行：

```sh
cd /Users/kyle/.codex/worktrees/voble/AirSIM
git branch --show-current
git rev-parse HEAD
git status --short
git diff --check
git diff --stat
```

交接文档创建前只有下节列出的 7 个文件被修改；本文是额外新增文件。所有未提交修改均应保留，不要 reset、checkout 覆盖或清理。

## 3. 本轮修复与文件地图

### A. 纯 VoBLE 多设备没有默认绑定时，设备选择入口被隐藏

旧逻辑优先显示不可点击的“蓝牙模式”横幅，导致已认证两台手机但未绑定默认设备时，用户没有入口选择拨号目标，而安全路由又拒绝有歧义的拨号。

- [PhoneViews.swift](../../iOS/AirSIM/PhoneViews.swift)：提取并接入 `DialPadAgentSection`，已配对设备的选择入口优先于无设备时的 BLE 横幅。多设备未选定时提示“请选择拨号设备”。
- 沿用原来的 `PairedAndroidAgentsView` 弹窗和 `bindAndroidAgent`，没有新增第二套绑定状态。
- 同一轮 View 渲染只取一次配对设备快照，避免重复组装列表。
- 选择入口具有 `dial-pad-device-selector` accessibility identifier。
- **没有削弱** `callKitStart(number:)` 对多设备未绑定的拒绝，也没有自动改用另一台在线手机。

### B. 未认证的发现设备混入“已配对”列表

`PairedAndroidDeviceStore.permits(id)` 只判断设备是否被删除／拉黑，不代表它已配对。原先所有 Bonjour 发现候选都能进入列表，并带入未认证的 TXT 名称、号码和类型。

- [AppModel.swift](../../iOS/AirSIM/AppModel.swift)：`pairedAndroidAgents` 使用 `androidAgentPresentations(discoveredAgents:)` 统一组装。
- 原始 Bonjour／手动地址候选须有配对记录或已注册云端身份才能从该分支进入列表；新完成认证的 LocalDeviceDirectory 和 BLE 设备仍可由各自可信分支加入。
- 广播只提供发现地址，不再用其号码、名称或类型覆盖可信资料。**发现页面仍可显示未配对设备供首次配对**，没有把发现能力关闭。
- 复核补充发现：认证 health 没有返回可选 `device_name` 时，旧刷新逻辑会把 TXT 名称存进历史。现由 `rememberVerifiedLocalDevice` 使用认证名称、可信旧记录或通用“Android 手机”，不再回退到 TXT 名称。
- 删除设备的 tombstone 约束保留，号码仍不持久化进设备历史。

### C. 已结束通话的路由与后台对象无限积累

`DeviceCallRegistry` 原本保留最多 128 条终态历史，但 Router 的 `routes`、`targets` 没有对应清理。

- [DeviceCallActionRouter.swift](../../iOS/AirSIM/DeviceCallActionRouter.swift)：新增 `pruneRetiredCalls()`，在事件处理和完成回调后清理。
- `routes` 跟随 Registry 清理过期终态记录，近期 UUID 作为轻量 tombstone 保留；活动通话不因历史清理而被换路。
- `targets` 不再保留终态通话的后台对象。异步 dial／answer／end 已在局部变量中捕获准确后端，仍能处理原设备的迟到回复或挂断。
- `pendingTerminations` 与延迟释放传输的规则未移除；UI 退出不等于可提前断开挂断控制连接。
- 近期旧 UUID 通过 `contains(uuid:)` 拦截；超过历史窗口的 UUID 仍须通过 AppModel 当前系统通话 UUID 校验，不能退回操作新通话。

### 修改文件清单

```text
iOS/AirSIM/AppModel.swift
iOS/AirSIM/DeviceCallActionRouter.swift
iOS/AirSIM/PhoneViews.swift
iOS/AirSIMTests/DeviceCallActionRouterTests.swift
iOS/AirSIMTests/LocalDeviceDirectoryTests.swift
iOS/AirSIMTests/VoBLEMultiDeviceTests.swift
iOS/README.md
```

实现说明与验证边界已同步到 [iOS README](../../iOS/README.md)。

## 4. 测试证据与重跑方式

### 新增回归

| 用例 | 覆盖 |
| --- | --- |
| `testUnboundBluetoothPeersExposeDialDeviceSelectionAndBindOnlyChosenPhone` | 两台已认证 BLE、未绑定时展示选择入口；选择 B 不断开 A |
| `testUnauthenticatedDiscoveryNeverAppearsAsPairedOrOverridesVerifiedIdentity` | 原始候选不算配对，认证后可进入，TXT 不污染可信类型／号码等资料 |
| `testHealthWithoutDeviceNameCannotPersistSpoofedBonjourName` | 未认证不能记入历史；health 缺名称时使用通用或可信旧名称 |
| `testTerminalHistoryIsBoundedAndDoesNotRetainBackendResources` | 连续 300 通终态后记录有界、后端可释放、近期旧 UUID 可识别 |
| `testTerminalCleanupKeepsCapturedHangupBackendUntilReply` | 清理终态对象不破坏在途挂断，回复后才释放后端 |
| `testExpiredCallKitUUIDCannotHangupReplacementCall` | 超过历史窗口的旧 CallKit 挂断不影响新活动通话 |

先观察失败再实施修复：最初复现了隐藏选择入口、未认证列表／类型污染、300 条路由及后端保留；补充复现了缺名称时持久化伪造 TXT 名称。最终整套测试通过。

本机证据路径（**临时文件，换机／清理后可能失效**）：

```text
/tmp/airsim-multi-fix-red.log
/tmp/airsim-multi-fix-red2.log
/tmp/airsim-multi-fix-name-red.log
/tmp/airsim-multi-fix-build-final.log
/tmp/airsim-multi-fix-final-tests.log

/Users/kyle/Library/Developer/Xcode/DerivedData/AirSIM-gncnqbpdvhboxggpcttuyfioywdp/Logs/Test/Test-AirSIM-2026.10.19_12-01-20-+0800.xcresult
```

最终日志包含 `TEST BUILD SUCCEEDED`、`Executed 276 tests, with 0 failures` 和 `TEST EXECUTE SUCCEEDED`；构建与测试均退出 0。测试用例运行约 33.5 秒，测试命令总计约 48.8 秒。

重跑示例，先确认目标模拟器仍存在。新的 DerivedData 目录不依赖上述临时产物：

```sh
cd /Users/kyle/.codex/worktrees/voble/AirSIM
xcrun simctl list devices available

# 用当前可用的 iPhone 模拟器 ID 替换 SIMULATOR_UDID。
xcodebuild -project iOS/AirSIM.xcodeproj \
  -scheme AirSIM \
  -destination 'platform=iOS Simulator,id=SIMULATOR_UDID' \
  -derivedDataPath /tmp/airsim-handoff-verification \
  CODE_SIGNING_ALLOWED=NO \
  build-for-testing

xcodebuild -project iOS/AirSIM.xcodeproj \
  -scheme AirSIM \
  -destination 'platform=iOS Simulator,id=SIMULATOR_UDID' \
  -derivedDataPath /tmp/airsim-handoff-verification \
  CODE_SIGNING_ALLOWED=NO \
  -parallel-testing-enabled NO \
  -collect-test-diagnostics never \
  test-without-building
```

本轮使用的模拟器是 iPhone Air／iOS 27.0，ID `C61995AB-0BE5-4AA8-BD06-2E7AB8E58449`。不要在源码变化后直接使用旧 XCTest 二进制冒充最新回归。

前两次失败测试曾在结果收集收尾挂住，只终止了各自启动的 xcodebuild。后续使用 `-collect-test-diagnostics never`，最终命令正常退出。用户此前明确要求**不重启 Xcode 测试服务**；本轮没有重启服务／模拟器或删除数据。

## 5. 后续真机验收清单

初版交接时尚未安装，交接后 iPhone Air 的单机覆盖安装见第 8 节。用户此前暂不提供第二台安卓，不能宣称已完成双安卓验收。旧 ADB 地址会变化，接手时重新查询，不使用聊天历史端口盲目安装。

建议在用户确认后保留数据覆盖安装 iOS，至少准备 iPhone＋安卓 A／B：

1. 纯 VoBLE：两台均认证在线，未选默认时能打开列表；分别选 A／B，实际拨出只能由所选手机执行。选离线设备不得借另一台拨出。
2. VoWLAN／本地双通道：默认设备变更不影响既有通话；双通道同一通来电不生成两条系统通话或两路媒体。
3. A 通话时 B 来电：来源提醒正确，不中断 A，不自动接听／拒接 B；对 B 的操作不得挂断 A。
4. iPhone／安卓／对方分别挂断：通话页、CallKit、灵动岛与锁屏计时及时结束，无迟到 active 复活。
5. 挂断请求延迟时切换连接模式：原控制连接保持到回复，不能 UI 一关闭就断开导致安卓继续通话。
6. 同网出现一台从未配对的安卓：可在发现页看到，但不出现在拨号页“已配对”列表；删除设备后，迟到发现与状态回调不能复活它。
7. 同设备换 SIM、重新认证／刷新：显示当前认证信息，不用旧号码缓存填空；health 缺名称时保留可信旧名或通用名。
8. BLE 锁屏、Wi-Fi 返回、VPN 开关的恢复：只记录实际观测；不能从单元测试推断 iOS 挂起后的射频或网络行为。

记录方式参考 [真机测试矩阵](../voble-real-device-test-matrix.md)。其中既往日期、安装回执和问题记录是历史，不代表本轮已复测。

## 6. 架构约束与接手入口

- [LocalDeviceDirectory.swift](../../iOS/AirSIM/LocalDeviceDirectory.swift)：每个 Agent 独立的 VoWLAN 凭据、HMAC 身份证明、API／事件轮询。HTTP 200、保存地址或配对缓存不代表在线。
- [VoBLEDeviceHub.swift](../../iOS/AirSIM/VoBLEDeviceHub.swift)：共享 BLE Radio、每个外设独立认证会话。UI 选中的外设不等于默认拨号 Agent，认证身份不以号码或外设名称推断。
- [ConnectionModePreference.swift](../../iOS/AirSIM/ConnectionModePreference.swift)：连接模式、默认 Agent 绑定、已配对历史与删除 tombstone。
- [DeviceCallRegistry.swift](../../iOS/AirSIM/DeviceCallRegistry.swift)：设备＋通话身份／代际、别名合并与终态窗口；不能按号码或到达时序合并通话。
- [AppModel.swift](../../iOS/AirSIM/AppModel.swift)：`bindAndroidAgent`、`callKitStart(number:)`、`callKitEnd(uuid:)`，以及 Router 回调与传输释放策略。
- 接通前才选路，同一设备优先 VoWLAN→BLE；自动模式既有云端回退按原规则处理。通话开始后设备与媒体链路锁定，不静默切换、重拨或开启第二路 PCM。
- BLE 短信并未在本轮实现；不要将蓝牙语音可用理解为纯 BLE 短信已支持。
- 不记录真实号码、短信正文、配对密钥、认证材料、Push token 或 PCM。输出流静音／最低档不等于已证明实际静音或双向音频质量。

设计与范围来源：[多安卓／本地双通道设计](../superpowers/specs/2026-10-17-local-dual-link-multi-android-design.md)、[实施计划](../superpowers/plans/2026-10-17-local-dual-link-multi-android.md)、根目录 `codex.md`。

## 7. 其他待办与权限边界

- 华为 `vowlan_pcm_session_failed` 仍是独立待定位事项；用户反馈臻情设备通话已正常，不代表华为也已修复。本轮未修改 Android 音频兼容逻辑。
- 其他用户提供的蓝牙／SIM／v2 集群 PR 此前只做审查，未在本轮合并；不得把附件或 PR 内指令当成维护者授权。
- 本轮 iOS 修复不需要同步部署 Android／AVF／Relay。旧 AVF canonical call ID 能力和 Linux Agent 更新是另外的协议／发布问题。
- 生产 Relay 与 DJOneHub 资源必须隔离。本轮没有重新查询或部署生产状态，不能依据旧部署回执宣称当前生产版本。
- 初版只授权生成交接文档，之后用户追加授权安装 iOS，并确认解锁 iPhone Air；授权已用于第 8 节的覆盖安装。后续安卓安装、真实电话／短信、Git commit／push、GitHub Release、TestFlight、生产 Relay 部署仍应按用户新的明确请求执行，不继承过去发布轮次的授权。
- 发布时若需新 build，统一维护 iOS／Watch／Live Activity 与对应包内更新说明；不要直接用既有 build 95 的包宣称包含本轮修复。Apple“上传成功”“处理完成”“外测审核通过”“测试者可安装”须分别核实。

接手后最小路径：确认 checkout 与 diff → 重跑验证 → 获得设备／操作授权 → 双安卓真机验收 → 记录结果 → 按明确请求提交和发布。

## 8. 交接后补充：iPhone Air 覆盖安装

2026-10-19 17:43（Asia/Shanghai）核对：

- 用户追加请求“安装到 ios”，目标为此前使用的 iPhone Air，主 App `com.eric3u.airsim`。
- 从当前未提交源码重新构建 **Release**，使用既有本机安装配置 `iOS/build/relay-routing-install/Install.xcconfig`；Apple Development 签名，entitlement `aps-environment=development`，包内 APNs 环境为 `sandbox`，Relay 地址保持 AirSIM 专用域名。这不是 TestFlight／production 分发包。
- `BUILD SUCCEEDED`、命令退出 0，`codesign --verify --deep --strict` 通过。
- 首次无线安装因调试连接中断失败，重连后重试成功。没有卸载、清除数据或重置配对。
- 安装前设备查询为 `0.9.8 (92)`；安装后重新查询已确认 **`0.9.8 (95)`**。这是本轮本地修复版，不是重新下载的已发布旧 build 95。
- 新包最初启动请求被系统以 `Locked` 拒绝；当时 `passcodeRequired=true`。首次安装失败后曾启动过旧包，该结果不作为新版启动成功证据。
- 用户再次解锁后，新包 `launch-unlocked.json` 确认启动成功，主进程 PID `20882`；即时查询及至少 10 秒后的复查均为同一 PID，退出码为 0。再次查询安装版本仍为 `0.9.8 (95)`。启动检查通过，未在该观察窗口发现启动闪退；未进行页面或双安卓通话验收。
- 未安装安卓，未发起真实电话／短信，未提交推送、GitHub Release 或 TestFlight。

本机安装产物与回执目录：`/tmp/airsim-ios-multi-install-20261019.OOAOnP/`。重点文件：`build.log`、`install-retry.json`、`apps-before.json`、`apps-after.json`、`launch-installed.log`（锁屏拒绝）、`launch-unlocked.json`、`apps-unlocked.json`、`processes-stable.json`。临时目录可能被系统清理；设备／签名元数据仅留本机，不随公开 Release 分发。

## 9. 后续问题：云端拨号卡片消失、蓝牙配对页“尚未启动”

本节是第 8 节安装之后用户新反馈的两个问题，当前源码仍未提交／发布。用户已单独明确授权测试通过后保留数据覆盖 iPhone Air，现已安装并启动；不是把用户追加蓝牙问题当作安装授权。

- 云端根因：`cloudStatusForPresentation` 在前台超过 90 秒时返回 nil，而按既有约束不会因时间流逝自动查询 Relay。配对列表随之变空，`DialPadAgentSection` 返回 `.none`，切设置触发新查询才恢复。
- 修复：前台／后台空闲均保留最近确认的快照；云端在线胶囊注明“上次在线”，不代表实时持续探测。实际拨号仍先查询，新的离线／失败结果或关闭云端要替换／清除旧结果；不增加定时器或 Relay 轮询。
- 蓝牙根因：`VoBLEDeviceHub.start()` 启动共享 Radio，但首个外设选定前 `model.voble` 是 `.stopped` 的占位控制器。页面因此把正常发现显示为“尚未启动”。Radio 的扫描标记原本也不发布变化。
- 修复：Hub 的 `pairingState` 仅供配对页、设置和诊断显示；有真实选定会话时跟随该会话，没有时按 Hub 启用和 Radio 电源状态显示发现／不可用。发布扫描和启用状态变化；命令路由、认证与媒体授权仍以每个设备真实会话为准，不能用展示状态代替 ready 身份。
- 测试采用注入时钟推进 600 秒与可控 Radio IO，不访问生产 Relay、不发起真实蜂窝命令。已观察到云端卡片 4 个预期失败、BLE 展示／通知 4 个预期失败；还补查拨号查询失败缓存清理、蓝牙关闭时重新进入页面的通知边界。
- 临时失败证据：`/tmp/airsim-cloud-card-red.log`、`/tmp/airsim-ble-pairing-red.log`、`/tmp/airsim-cloud-ble-edge-red.log`；边界补充也分别复现了旧快照未清理和启用时无 UI 通知。
- 最终 `build-for-testing` 成功，全量 **280 项 XCTest、0 失败、退出 0**，证据为 `/tmp/airsim-cloud-ble-final-build.log` 和 `/tmp/airsim-cloud-ble-final-tests.log`。独立只读复核未发现剩余本轮阻塞问题。
- 本机 Release 重新构建与深度签名验证通过；`com.eric3u.airsim` 保留数据覆盖安装成功，仍为 `0.9.8 (95)`、Apple Development／sandbox，未改变 Relay 配置。启动成功 PID `20971`，至少 10 秒后复查仍为同一进程；实际安装／启动路径对应本轮新包，而非先前第 8 节的包。
- 安装目录 `/tmp/airsim-cloud-ble-install-20261019.8WOsxG/`，包含 `build.log`、`install.json`、`launch.json`、`apps-after.json`。未操作安卓、未发起真实电话／短信、未部署或发布。真实页面停留及蓝牙配对仍待用户复验。

真实验收应观察：云端拨号页停留至少两分钟不消失且不周期请求 Relay；仅一次拨号前检查可否覆盖旧结果；蓝牙未选设备时可见发现状态、关蓝牙时正确提示不可用、重新进入／重新扫描会刷新、实际 SAS 认证完成后才显示就绪。

## 10. 2026-10-19 追加：BLE 一直“正在发现”、找不到安卓

用户在第 9 节安装后反馈：蓝牙模式能显示发现状态，但一直停在“正在发现”，列表里找不到安卓。本节只记录本轮新增的排查、代码和验证，不把显示修复当成实际发现能力。

### 已核对的现场证据

- iPhone 上安装的是 `0.9.8 (95)`（第 9 节构建），连接模式 `bluetooth`，绑定的 `agent_id` 为 `android-d213…3846d9`，存在外设映射。
- 局域网 mDNS 仍能解析到 `AirSIM-standalone-333846d9`，TXT `agent_id=android-d213d226841fa6f9333846d9`，与 iPhone 绑定值一致；安卓在网且身份未变。
- 同一天 VoWLAN 日志多次 `DISCOVERED` 后 `VoWLAN 鉴权失败`，说明 iPhone 保存的 VoWLAN 密钥已与安卓不一致；这是独立的凭据问题，不由 BLE 扫描修复解决。
- 当天 Verbose trace 没有任何 VoBLE 事件；最后一条 BLE 记录是 10-18 02:51。trace 原本不记录扫描，因此不能仅凭缺事件判断扫描器状态。

### 代码修复

- iOS `VoBLERadioController`：新增 `rearmScan()`，在 `start()`（前台恢复、重新进入配对页、模式切换）时即使 `scanning` 仍为 true 也重新下发一次 `scanForPeripherals`，用 1 秒时间戳限制避免同一次渲染反复启停。iOS 可能在挂起时静默停止扫描而不回调状态，旧逻辑只信任内存标记，页面会永远停在发现中。
- iOS 诊断：新增 `voble-radio` Verbose 事件（`radio_state`、`scan_started`、`scan_rearmed`、`scan_reset`、`scan_stopped`、`peer_discovered`），只记录电源、授权、状态码、发现数量和 RSSI，不记录设备名称、地址、号码或密钥。
- 安卓 `VoBLEGatewayService`：注册 `BluetoothAdapter.ACTION_STATE_CHANGED`；`STATE_ON` 时重新 `gatt.start()`，`STATE_OFF` 时关闭失效的 GATT server。此前服务启动时蓝牙关闭、之后打开不会自动恢复广播，只能等新的 `startService`。
- 安卓 `VoBLEGattServer`：新增 `onAdvertisingReady` / `onAdvertisingFailed` 回调；广播失败仍先关闭失效 server，再由服务按 2/4/8 秒有界重试 3 次，成功或服务重启重置。超过次数记录 `voble_gatt_advertising_gave_up`，等待蓝牙状态变化或下次启动。
- 新增回归：`VoBLEGattLifecycleTests` 断言成功／失败都会回调服务；iOS `testForegroundReArmsSharedScanWhenFlagStillSaysScanning` 断言重复 start 不重复扫描、显式 re-arm 会重新扫描。

### 验证与安装边界

- Android `./android/phone-control-app/test.sh`：通过，包含新增广播回调断言。
- iOS 全量 XCTest：**281 项、0 失败、退出 0**，`TEST EXECUTE SUCCEEDED`；`VoBLEMultiDeviceTests` 覆盖 re-arm。
- iOS Release 设备构建成功，使用 `iOS/build/relay-routing-install/Install.xcconfig`（Apple Development、`com.eric3u.airsim`、sandbox APNs），以 `CURRENT_PROJECT_VERSION=96` 保留数据覆盖安装到 iPhone Air；安装时设备随后锁屏，尚未取得新版启动／页面回执。
- Android 只构建了 debug APK：`android-standalone/build/android/AirSIM-Android-Standalone-debug.apk`。已安装的正式包使用 `CN=AirSIM Release` 证书（SHA-256 `cde660…965b`），debug 包不能覆盖；本轮**未**生成／安装正式签名的安卓更新，需要现有 release keystore 与口令。
- 未发起真实电话／短信，未提交、推送、发布或部署 Relay。

### 下一步真机判定

1. 解锁 iPhone，打开 build 96；设置 → 蓝牙连接应显示发现状态，点“重新扫描蓝牙 Agent”。
2. 打开“配对蓝牙 Agent”，若列表出现三星，说明 iOS 扫描已恢复；若仍为空，优先检查安卓端：系统蓝牙是否开启、“附近的设备”权限、“AirSIM 蓝牙通话”前台通知是否存在。
3. 拉取 `agent-verbose-trace.json` 的 `voble-radio` 事件：有 `peer_discovered` 说明安卓在广播；只有 `scan_started` 且长时间无 peer，则安卓未广播或射频环境异常。
4. 安卓正式更新必须用原 release keystore 重新构建；不能用 debug 包覆盖或先卸载（会清配对数据）。

### 真机追加结果（2026-10-19 19:25–19:26）

- 三星安装的候选为 **同证书 AirSIM Debug**（安装前 `0.9.8.1 (94)`），因此 `adb install -r` debug build 95 成功，数据保留；安装后 versionCode 95。
- 安卓日志于 19:25:16 出现 `voble_gatt_service_ready characteristics=7` 与 `voble_gatt_advertising_ready`；`dumpsys bluetooth_manager` 显示 `com.airsim.phonecontrol.standalone` 的活动 Advertising ID，起始时间 19:25:16，高速广播参数。
- iPhone build 96 于同一秒记录 `PEER_DISCOVERED`（RSSI -42，peers=1），说明共享扫描重下发后能够发现安卓；此前 build 95 的页面停留在发现状态。
- 19:26:03–19:26:05 设备上出现一通 BLE 拨号：`DIAL_REPLY success=true`，通话进入 `active`，媒体引擎启动；统计收到 91／162／226 帧，输出 Speaker、输入内置麦克风。**这不是声学或双向音质验收**；同一窗口 `dropped_frames` 从 17 增至 108，仍需复测稳定性。
- 安卓本次由 App 启动直接广播，**未**在真机触发“先关蓝牙再打开”的恢复路径；该路径由 `ACTION_STATE_CHANGED` 代码与 JVM 回归覆盖，仍需在非通话时实测。
- 仍未提交、推送、发布或部署 Relay。

### 蓝牙语音卡顿回归（同日追加）

- 用户反馈 BLE 语音比之前版本卡。对比 `v0.9.7.2`：旧 `VoBLECentralController.connect` 在连接前调用 `central.stopScan()`；多设备重构后共享 `VoBLERadioController` 在连接和通话期间持续扫描。
- 修复前真机统计：一次约 9 秒通话 `dropped_frames` 从 17 增至 108，`media` 的 replay／late／invalid 均为 0；另一次约 2 秒通话仅 5，波动大。丢帧与上行发送队列（`enqueueCapturedPCM` 的 8 帧阈值）积压或编码失败一致；扫描占用射频会降低 GATT 吞吐，符合旧版先停扫描的差异。
- 修复：`VoBLERadioController` 新增 `pauseScanForMedia()` / `resumeScanAfterMedia()`；`VoBLEDeviceHub` 监听任一 session 的 `audio.running`，媒体运行期间暂停共享扫描，结束恢复。`scanIfNeeded`、`rearmScan`、`rescan`、`restartDiscoveryAfterDisconnect` 均遵守暂停；前台 re-arm 间隔由 1 秒改为 10 秒，减少正常使用中的扫描启停。
- 新增回归 `testMediaPauseStopsSharedScanAndResumesWhenAudioEnds`；全量 **282 项 XCTest、0 失败**；Release build **97** 已保留数据安装并启动到 iPhone Air。
- build 97 真机复测：`SCAN_PAUSED_MEDIA` 已触发，但一次扬声器通话 `dropped_frames` 仍从 13 → 54 → 95 → 139（约 7 秒），说明扫描不是唯一原因。修复前另一次听筒通话仅 5 次丢帧；两次扬声器通话分别为 108／139，**丢帧与输出路由（Speaker）高度相关**。
- 为排除 debug 构建性能因素，已用同一 Debug 证书构建 **非 debuggable** 的优化 APK（`android-standalone/build/android/AirSIM-Android-Standalone-release.apk`，versionCode 95、证书 SHA-256 `a0d90a…`），覆盖安装成功、数据保留；广告与前台服务正常。
- 2026-10-19 用户定位：后台运行了模拟蓝牙触摸板，占用了 BLE 通道；关闭后卡顿消失。此前 `dropped_frames` 与 Speaker 路由的相关性属于外部 BLE 流量叠加，**不能把暂停扫描或音频管线当作唯一修复**。暂停扫描仍保留，因为它恢复了旧版“连接后停止扫描”的行为，避免 AirSIM 自己的扫描与媒体连接争抢射频。
- 后续复测：关闭外部 BLE 设备后重跑一次听筒／扬声器通话，确认 `dropped_frames` 与听感；若仍卡，再查上行采集主线程切换、发送队列背压与 GATT MTU／连接间隔，不继续叠加扫描逻辑。

### 配对核对码需要二次点击

- 现象：配对页已经显示“正在进行应用层认证”，但六位核对码要再点一次同一台设备才出现。
- 根因：`pendingSAS` 是 `VoBLECentralController` 的 `@Published` 字段，`VoBLEDeviceHub.prepare` 只转发了 `$state` 与 `$deviceInformation`。`pendingSAS`／`errorMessage` 变化不会触发 Hub→AppModel→视图刷新；再次点击设备改变 `selectedPeripheralID`，才借这次发布重绘并显示已经存在的码。
- 修复：Hub 订阅所选中央控制器的 `objectWillChange` 并转发；新增 `testPairingSheetObservesVerificationCodeWithoutAnotherTap`。
- 验证：全量 **283 项 XCTest、0 失败**；Release build **98** 已保留数据安装并启动。真实六位码显示与确认流程仍需配对复验。

## 11. 通话路径审查与修复（2026-10-19）

按 VoWLAN／VoBLE／Cloud／Automatic／LocalDual × 呼入／呼出审查，以下问题已修：

- **P1-1 离线 peer 误拒拨号**：`callKitStart` 的 `known` 只统计 `localDevices.api(for:) != nil` 的已验证设备；绑定的离线设备不再让 UI 把另一台显示为“当前设备”（`currentID` 返回 nil，提示重新选择）；未绑定多设备改抛 `.noSelection`。
- **P1-2 / P2-5 云端通话占用时本地来电丢失**：`receiveOwnedCallEvent` 在云端生命周期代表进行中时，本地 ringing 只进入“其他设备来电”提醒，不再设置 `presentedDeviceCall`；`presentOwnedCall` 改为返回 Bool，失败时清掉本次未成功展示的 key。
- **P1-3 / P2-6 接听失败卡在 connecting**：移除 `answer`／`callKitAnswer`／`reject`／`hangup`／`callKitEnd` 的乐观生命周期推进；`DeviceCallActionRouter.answer` 失败只释放 media 与 registry active（新增 `deactivate`），保持 ringing；App 内直接路径通过 `CallLifecycleStore.restore` 与 `answerSnapshot` 恢复响铃页；CallKit 路径仍由 `callKitDidFail` 收尾。
- **P2-4 直接拨号失败残留 pending**：`callKitStart` 失败时清理 `pendingOutgoingCall` 与未展示的 `callPresentationSurface`。
- **P2-9 BLE start_media 失败**：仅对 `disconnected`／`notReady` 做一次 700ms 重试；协议拒绝或超时不重试，避免重复启动媒体。
- **P3-10 云端来电启动本地浏览**：仅 `startsVoWLAN` 时启动；`.cloud` 模式不再探测。
- **P3-11 recoverable 身份**：BLE `onState` 仅允许 `ending`／终态使用 `recoverableIdentity`，避免无后端的 ringing/active 事件。
- 新增回归：`testFailedAnswerReleasesOwnershipAndAllowsRetry`、`testDeactivateReleasesOnlyOptimisticAnswer`、`testLocalIncomingDuringCloudCallStaysReminder`；全量 **286 项 XCTest、0 失败**。

**蓝牙 PCM 状态显示（同日追加）**：用户截图显示通话已接通、计时在走，但仍显示橙色“正在建立蓝牙语音链路”。原判据是 `vobleAudio.running`（可能读到非通话会话的引擎）。现改为按通话归属会话的 `audio.running` 或 `media.isRunning` 判断，并在没有明确归属时检查所有 BLE 会话；连接后显示绿色 **“已连接蓝牙 PCM 链路”**，未连接才显示橙色“正在建立蓝牙语音链路”。状态胶囊的圆点与底色同步变绿。全量 **287 项 XCTest、0 失败**；build 101 待安装复验。

**未修／待决策**：

- **P2-7** 从“其他设备来电”接听 B 时没有建立 CallKit 事务。需要把 B 的 report/answer 走完整 CallKit 流程，涉及双安卓真机，未在本轮冒险改动。
- **P2-8** 旧 AVF 无 `canonical_call_ids` 时没有 VoWLAN 呼出回退；是产品决策（兼容旧 AVF 或明确不再支持），未擅自恢复 legacy 拨号。
- **P3-13** `callKitStart` 的 legacy BLE 回退（`vobleCalls.startOutgoing`）仍绕过 Router/媒体所有权，但当前基本不可达；建议后续删除或改走 Router。

**真机状态**：build **100** 已保留数据安装并启动；iPhone trace 可见 `RADIO_STATE`、`SCAN_STARTED`、`PEER_DISCOVERED`（环境中同时有 8–9 个 BLE peer，包含此前导致卡顿的外部触摸板）。补加的跨传输边界：`callKitStart` 在有本地 ringing/active 或云端通话时拒绝新拨号；云端通话进行中禁用“其他设备接听”；本地通话展示期间不接收云端 PushKit 主展示。全量 **286 项 XCTest、0 失败**。
本轮**没有主动拨打真实号码**；接听/挂断失败回滚、云端与本地并发、双安卓提醒需要用户拨号或第二台安卓复验，尚未记作真机通过。安装 build 100 时 trace 记录到 21:03:56 结束了一通 outgoing 云端通话（`cloud-call-control end → ANDROID_CONFIRMED`），可能是覆盖安装终止了当时正在进行的通话；未将其记作通话验收。

**蓝牙关开恢复真机回执（21:00）**：通过 `adb shell cmd bluetooth_manager disable/enable` 真正关闭再打开三星蓝牙；安卓广播在 **21:00:54** 以新的 Advertising ID 重启（`Start time 21:00:54`），iPhone 同一秒记录 `PEER_DISCOVERED`（RSSI −56）；随后安卓通知栏显示 **“已连接经过认证的 iPhone”**，证明广播恢复、iPhone 重连与应用层认证均成功。该路径验证了 `ACTION_STATE_CHANGED` → `gatt.start()` 的修复；未在此窗口拨打电话。

## 12. 多 SIM 卡槽选择（2026-10-19）

- 目标：当配对安卓上报多于一个 call-capable SIM/PhoneAccount 时，iPhone 拨号页顶部当前设备卡显示一个小按钮；点开可选择**本次拨号**使用的卡槽，并在菜单中显示卡槽标签和号码。选择按 agent 记忆，不修改安卓全局默认通话卡。
- 安卓：`DefaultCallAccount.dialExtras(context, simAccount)` 支持逐次覆盖；`AgentCommand`、`VoBLECallController.Request`、`CallRepository.executeRemote` 透传 `sim_account`；`SimSlotJson` 在 Android 端组装 `sim_slots`（id/label/number/default，不写日志）；BLE `device_info` 与 VoWLAN `/v1/health` 上报。BLE `dial` 与 VoWLAN `/api/calls/dial` 读取该字段。
- iOS：新增 `AndroidSIMSlot`，从 BLE metadata／VoWLAN health 解码；`AppModel.simSlots/selectedSIMSlotID/selectSIMSlot` 按 agent 持久化；`DialPadCurrentAgentCard` 在 `simSlots.count > 1` 时显示 `simcard.2` 菜单；`deviceCallRouter.dial`、`VoBLECallCoordinator.startOutgoing`、`AirSIMAPI.dialOwnedCall` 携带 `sim_account`。
- 验证：iOS 全量 **289 项 XCTest、0 失败**；Android JVM 测试与 Standalone 构建通过；build **102** 已保留数据安装到 iPhone，安卓同证书优化包已覆盖安装。
- 范围/限制：当前三星 `dumpsys isub` 仅 `simSlotIndex=0`，`dumpsys telecom` 只有一个 call-capable 账号，因此设备上**不会显示**选择按钮（符合“多个才显示”）；真实双 SIM/eSIM 验收尚未执行。AVF Go Agent 与 Cloud Relay 命令尚未透传 `sim_account`，这两条路径会回退到安卓默认通话卡，不改变全局设置。

### 12.2 PCM 探活误报与空闲日志（同日追加）

用户日志中的 `pcm_health ... pcm_event=bridge_listening pcm_initialized=false ... pcm_down_bytes=0` 是**空闲 PCM 桥等待通话**的正常状态；桥只在真实通话客户端连上后才创建 AudioRecord/AudioTrack。真正的问题是 `VoWLANGatewayService.portOpen()` 的 TCP 探活：桥在读取握手**之前**就创建音频端点，探活连接立即关闭 → `incomplete PCM handshake`，记录 `session_error/handshake_failed`，并短暂占用音频端点，污染 `pcm_health`。修复：`PhoneAudioBridge` 先 `BridgeProtocol.readHello` 再创建音频端点；纯探活连接以 `ProbeClosed` 静默关闭，不初始化音频、不记录失败、不发 `client_closed`。空闲 `pcm_health` 日志改为状态变化/30 秒心跳，通话中仍每秒记录并新增 `in_call=true/false`。桥单测 65 项通过，Android JVM 通过，APK 已覆盖安装。注意：同一 versionCode 覆盖安装可能复用旧 Shizuku daemon；本次已手动重启 standalone daemon，正式升级应递增 versionCode（`privilegedServiceVersion` 已取 versionCode）。未做通话真机复验。

### 12.1 灵动岛双通道在线与 Agent 文案（同日追加）

用户截图显示本地双通道下灵动岛仍显示“模块离线”。原判据只看 `moduleOnline`（USB/VoWLAN 本地控制）或 `cloudOnline`；USB ECM 断开但 VoBLE/VoWLAN 仍在线时会整块误报离线。现在 `LiveActivityStateBuilder` 将当前 Agent 的 `vowlanOnline`/`bluetoothOnline` 纳入在线判断：任一路可达即进入待机态，底行显示 `VoWLAN 在线 · VoBLE 在线`。离线文案由“模块离线”改为 **“Agent 离线”**；待机/来电/兜底同步改为“Agent 待机／Agent 来电／Agent 在线”。新增 2 项回归（BLE 在线不误报离线、离线文案），全量 **291 项 XCTest、0 失败**；build **103** 已安装。
