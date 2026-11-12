# DSDS、通话卡槽与配对时钟（工作区候选，2026-10-20）

本文件记录未发布的工作区改动；不代表已发布 APK/IPA、TestFlight 或生产 Relay。

## 协议与行为

- 配对 GET /pair/v1/info 新增 server_time（毫秒）。iOS 手动配对把它换算为 clock offset，随 VoWLANCredential 持久化；VoWLANRequestSigner 的默认时间戳使用该 offset。旧 Android 不返回该字段时 offset 为 0，保持兼容。
- sim_slots 新增可选字段：slot_index、sub_id、carrier_name、is_embedded、is_default_voice、is_default_sms。iOS 的 SIM 菜单显示这些元数据。
- 短信：iPhone 使用当前 agent 已选 SIM 卡槽，/api/sms/send 携带 sim_account；Android SMSCommandExecutor 解析对应 subscription 后发送。未选择时仍走系统默认短信 SIM。
- 通话：Android 通话事件/status 新增 slot_index/slot_id，由 Call.Details.getAccountHandle() 解析；iOS CallRecord 在通话界面显示实际卡槽（VoWLAN 路径）。
- 订阅变化：Android SIMSlotObserver 监听 SubscriptionManager；VoWLAN /api/events 返回 sim_revision/sim_slots，iOS 用事件覆盖刷新 SIM 菜单。BLE-only 模式仍在下一次 device_info/前台刷新时更新，没有新增未经认证的推送通道。
- StandaloneLongPoll 缺省 after=0，新客户端首次 poll 不再报 cursor 错误。端口仍以 Bonjour/direct route 的实际 localPort() 通告；未引入 v2 cluster。

## 验证

- iOS 292 项 XCTest，0 失败。
- Android phone-control-app/test.sh 全量通过；Standalone debug APK 构建成功。
- 未做 Voice/SMS 真机双向复验；双 SIM 设备、华为 BLA-L29 PCM、BLE-only 实时刷新仍需实测。当前测试机的 Redmi/官方 0.9.8.2 不含本轮 Android 变更，需新构建。

## KernelSU root SMS（0.9.8.4 / 98）

- 发送顺序：KernelSU root → Shizuku shell → 普通 App SmsManager。
- Root：RootSmsSender 用 su -c 启动 app APK 内的 RootSmsMain；SMS JSON 放在 App 私有 cache 文件，经路径传给 helper，正文不进入 shell 命令行；helper 以 UID 0 调 SmsManager，返回 ok:<segments>。
- 不把 AirSIM 设为默认短信应用；不改默认 SIM。KernelSU 首次调用会弹一次 root 授权，之后按 root 通道发送。
- 失败时回退 Shizuku/旧路径；未在 KernelSU 小米真机验证，MIUI 若仍按 package 拦截需回传弹窗/日志。
- 全局 root 通道（0.9.8.5 / 99）：ShizukuBridgeManager 优先 Root；RootBridgeTransport 通过 su 启动 RootBridgeMain，复用 ShizukuBridgeUserService 的 PCM、静音、audio snapshot、拨号角色和短信；TCP loopback + 一次性 token；失败回 Shizuku。
- Root 启动时会请求一次 KernelSU 授权；尚未在 root 真机验证。
- 设置页“Shizuku / Root 权限与 PCM 桥”新增权限通道选单：自动（Root 优先）、仅 Shizuku、仅 Root；另有 Root 授权/重试与刷新状态。选择持久化，切换会重建 PCM 桥。

## 私有网段与首选端口（0.9.8.7 / 101）

- Android 设置页“私有网络与端口”：可追加 CIDR（如 30.0.0.0/8）；保存后立即作用于 VoWLAN 控制/PCM 对端策略、Bonjour 与手动地址、配对放行。
- 可设置 VoWLAN 控制端口（默认 7592）、PCM 端口（默认 7593）、配对端口（0=自动）。端口被占用或受限时自动改用空闲端口，Bonjour 与配对页通告实际端口；保存后重新建立网关，通话中不中断，下一轮生命周期生效。
- iOS 设置页“私有网络”同样可追加 CIDR，保存后重新发现；手动配对提示与占位符已更新。
- 安全边界：公网地址在任何配置下都不视为私有；127/8 仍只用于原有回环语义，手动配对继续拒绝；HMAC、nonce、时间戳校验不变。

## VoBLE 本机静音与下行采集（0.9.8.8 / 102）

- 现象：VoBLE 通话时 iPhone 听不到对方，必须在 Android 手动调大音量后才恢复，同时 Android 也开始外放。
- 根因：0.9.7.2 起三星使用“最低音量（通常为 0）”静音本机输出；该机型的 `VOICE_DOWNLINK` 采集与输出音量耦合，index 0 同时把转发给 iPhone 的下行采集压成静音。
- 修复：三星改用最低**非零**音量（`MINIMUM_NONZERO_VOLUME`），保持采集路径打开；通话结束恢复原音量/静音位。VoBLE/VoWLAN 都走采集安全策略，传输标签保留用于诊断。
- 注意：本地听筒在最低非零档可能仍有轻微声音；若实测仍明显外放，下一步改为“保持采集音量 + 仅按设备输出 index 0”的混合静音。
- 验证：Android 全量测试通过（含新增 VoBLE 回归用例）；尚未在三星真机复测。

## 灵动岛动作与云端挂断（0.9.8 / 109）

- 灵动岛按钮原先写死 USB ECM 地址 http://192.168.225.1:7575，云端/VoWLAN 通话点击挂断必然失败并抛错，活动也不会结束。
- 修复：LiveActivityIntent 优先调用 App 内的统一动作（cloud/VoBLE/VoWLAN 都复用 answer/reject/hangup），失败才回退旧 USB HTTP；AppModel 在进程启动时注册该桥。
- 云端远端挂断：云端生命周期进入终态时，额外强制把灵动岛刷新为待机，避免 applyCallLifecycle 被乱序事件拒绝后仍显示通话中；同时清理 currentCallTransport，防止残留的 .bluetooth 让下一次云端呼入被错误按 VoBLE 接听。
- VPN 文案：只有 100.64/10（Tailscale/CGNAT）才显示“VPN 直连”，普通 10/172.16/192.168 私网显示“同一局域网”，即使实际走系统路由。
- 已知：该组件的旧回归用例 testLateNativeIncomingReportFailureCannotResetReplacementUUID 在基线 HEAD 上也失败，与本次无关。

## 灵动岛通话结束与锁屏布局（0.9.8 / 111）

- VoBLE/VoWLAN 的灵动岛按钮原先用 Link(airsim://...) 打开 App，再进入 VoBLE 专用处理；对云端/已结束通话会提示“该蓝牙通话已经结束或被另一通电话替换”，且活动不结束。
- 修复：所有传输统一使用 AppIntent（LiveActivityIntent 在 App 进程执行，走 AppModel 的 answer/reject/hangup）；旧 URL 入口也改走同一路径。
- 远端挂断：终态即使被 applyCallLifecycle 拒绝，也强制把 Live Activity 刷新为待机（force update），计时器立即停止；**不 end 活动**，否则后台常驻灵动岛会消失。过期点击同样回到待机。
- 锁屏布局：通话阶段不再叠加 Agent 摘要行，收紧水平/垂直间距，通话计时与号码支持缩放并限制单行，避免超出系统 Live Activity 边界。

## 灵动岛只保留 Agent 状态（0.9.8 / 113）

- 用户决定：通话全部交给 CallKit 管理，灵动岛不再承载任何通话状态。
- LiveActivityStateBuilder 不再产出 incoming/active/held，只产出 standby/cloudStandby/offline（Agent 名称、号码、VoWLAN/VoBLE/云端在线状态与信号仍保留）。
- 旧版本已创建的通话态活动在渲染时归一化为待机；挂断/远端挂断只刷新待机，不结束活动，后台仍显示 Agent 状态。
- 灵动岛和锁屏的通话计时、接听/拒绝/挂断按钮已删除；CallKit 负责接听、挂断与通话界面。
