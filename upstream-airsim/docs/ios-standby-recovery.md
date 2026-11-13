# iOS 待机恢复边界与诊断

日期：2026-10-21。适用于 iOS App 0.9.8（build 113 观察，build 120/121 修复验证中）。Android 端为 Standalone 0.9.8.8 (102) 及之后的本地合并版。

## 已有恢复机制

- **Wi-Fi 路径变化**：`VoWLANController` 的 `NWPathMonitor(requiredInterfaceType: .wifi)` 监听可用性；变化时递增 `revision`、取消旧探测、重建 Bonjour 浏览器，并在 0/2/5 秒做有界探测。旧网络的异步结果由 `identityEpoch`、`probeGeneration`、`browserLifecycle` 和 `LocalDeviceDirectory.verification` 丢弃。
- **新 IPv4/端口**：Bonjour 重新发现后，`LocalDeviceDirectory.verifyPairing` 用原 Keychain 配对密钥重新做 nonce/proof 认证，成功后替换 endpoint 和 `transportEpoch`；不需要重新配对。认证失败不会删除 Keychain 或配对记录。
- **回前台**：`AppModel.didBecomeActive()` 在空闲时重建 VoWLAN 浏览器并探测；轮询失败时 `nextAgentEvent()` 调用 `recoverIfNeeded()`，恢复门限为 10 秒，之后继续按轮询退避重试。
- **通话中**：恢复任务等待通话结束，不做媒体切换；前台恢复只在 **没有活动通话** 时重建 Bonjour（本次修复）。
- **本地与云端分离**：本地 VoWLAN 不可达时仍查询 Relay 心跳；Cloud 在线而本地不可达不会把整台 Android 标成完全离线。Automatic 只会在建立通话前选择通过验证的路径。
- **Android 侧**：内置 Agent 为前台服务（START_STICKY），有 BootReceiver 和循环重试；OEM 电池策略仍可能杀掉进程。

## 系统边界（不能承诺的部分）

1. **iOS 挂起**：App 被系统挂起后，Bonjour、NWPathMonitor 和普通定时器都可能暂停。下一次获得运行机会（回前台、PushKit/BLE 事件、系统后台唤醒）才会复核；挂起期间不保证实时恢复。
2. **用户强制退出 iOS App**：系统不会自动重新拉起，APNs/PushKit 也不会在强制退出后恢复旧 CallKit；必须由用户重新打开。
3. **Android App 被 OEM 强停/省电策略杀掉**：iOS 无法远程重启 Android 进程。Android 的 START_STICKY/BootReceiver 只能覆盖系统正常重启和开机；部分 OEM 需要关闭电池优化/允许自启动，或手动打开 App。不能把“打开 Android App 后恢复”归因于 iOS 恢复失败。
4. **通话中的网络切换**：当前策略是等待通话结束再恢复，不做无缝媒体切换；不能承诺通话中换 Wi-Fi 不中断。
5. **APNs 不保证即时送达**：后台 call_owner/call_state 可能延迟、合并或丢弃；客户端获得运行机会后仍需以权威状态幂等清理旧来电。

## 诊断记录

Verbose 中已有、且不含号码/密钥/短信内容的字段：

- `vowlan / network_changed`：Wi-Fi 可用性与 revision
- `vowlan / browser_restarted`、`browser_failed`
- `vowlan / verified`、`failed`：认证/健康检查结果
- `vowlan / network_recovered`、`network_recovery_pending`
- `vowlan / fallback`：LAN → Tailscale/已保存直连
- `lifecycle / foreground`、`background`：call_active、模式、VoWLAN 状态、是否已启动发现
- Android：`vowlan_ready`、`vowlan_control_failed`、`vowlan_control_forwarded`、Agent 心跳/重试日志

这些记录只包含主机/端口/状态/代数，不包含配对密钥、号码或消息正文。

## 验证建议

1. 两台手机进入新的共同 Wi-Fi，确认无需重新配对，日志出现新的 `DISCOVERED` 和 `VERIFIED`。
2. 锁屏 10–30 分钟后回到前台，确认 `lifecycle / foreground`、`network_changed`、`verified` 出现，旧 endpoint 不被复用。
3. 保持 Cloud 在线但关闭 Wi-Fi，确认 UI 显示云端在线而不是整机离线，Automatic 仍可在建立通话前走 Cloud。
4. 通话中回到前台，确认不会重建 Bonjour 或替换当前路由。
5. 强制退出 App 后再打开，确认 Keychain/配对仍在，但恢复必须由这次启动触发。
