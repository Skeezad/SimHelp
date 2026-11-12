# AirSIM Handoff：通知转发、CallKit/VoWLAN 与 Relay 降级

交接日期：2026-10-26（Asia/Shanghai）。本文是本地工作区快照，不是发布、真机或生产验收回执。

## 1. 接手结论

当前主线已包含通知转发第一版、Bark V2、飞书响应校验、来电去重修复和 CallKit/云端链路多项修复。

- **分支**：`VoBLE` 与远端 `main`、`AirSIM-ZTE` 均位于 `a60962a`（本文提交前）。
- **应用版本**：Android `0.9.8.12 (117)`，iOS/Watch/Live Activity `0.9.8 (141)`。
- **发布状态**：`v0.9.8.12` 已发布；TestFlight 141 曾上传并 processing，接手时需重新查询 Apple 实际状态。
- **未发布**：本轮通知转发、Bark/飞书修复、Relay APNs 解耦仍在工作区，未形成新的 Release/TestFlight。
- **最大外部阻塞**：Cloudflare Durable Objects 免费额度已耗尽，Worker 仍会记录 `Exceeded allowed volume of requests in Durable Objects free tier`。这会阻断 Relay 注册、媒体、心跳和部分命令；APNs 路径已做降级，但不能保证云端通话完整可用。

## 2. 工作区与分支

| 项目 | 快照 |
| --- | --- |
| VoBLE worktree | `/Users/kyle/.codex/worktrees/voble/AirSIM` |
| main worktree | `/Users/kyle/codex project/AirSIM` |
| 远端 | `origin/VoBLE`、`origin/main`、`origin/AirSIM-ZTE` |
| 共同 HEAD | `a60962a`（`关键合并 flag`） |
| main 未跟踪文件 | `dist/`、`docs/assets/`、`video/`、部署指南 docx 等；不要清理 |
| main stash | `stash@{0}: On main: pre-main-sync 2026-10-26` |
| 本地 main | 已快进到 `a60962a`，未跟踪文件保留 |

`AirSIM ZTE` 因 Git 不允许空格，实际分支名为 `AirSIM-ZTE`。

接手先运行：

```sh
cd /Users/kyle/.codex/worktrees/voble/AirSIM
git status -sb
git branch -vv
git rev-list --left-right --count origin/main...origin/VoBLE
git stash list
```

## 3. 通知转发（本轮主要新功能）

### 配置入口

iPhone：

```
设置 → 通知转发
```

支持渠道：

- Bark
- Discord
- Slack
- 企业微信
- 飞书自定义机器人
- Telegram Bot
- QQ 官方 Bot
- 通用 Webhook

每个目标独立配置：

- 短信 / 来电 / 未接来电开关
- 是否包含正文、号码
- 普通模板
- 未接来电独立模板
- 签名/Token/Chat ID/Device Key

### 下发方式

转发配置只随**加密配对注册包**下发：

```
iPhone NotificationForwardingConfig
→ AgentPushRegistration.notification_forwarding
→ 加密 pairing registration
→ Android ForwardingConfigStore
```

Relay 注册前会剥离 `notification_forwarding`，Webhook URL/token 不上传 Relay/APNs。

### Android 发送

`NotificationForwarder` 直接 HTTPS POST：

- 不经过 Relay
- 不经过 APNs
- iPhone 被划掉/关机不影响
- 失败不阻塞短信/通话
- `delivery_id` 去重；来电使用 `call_id + state + direction`
- 单线程后台队列

## 4. 本轮修复

### 短信转发

旧 Android SMS 事件没有 `event` 字段，Forwarder 只判断 `incoming_sms`，导致所有渠道短信都不转发。

修复：

- `WireJson.smsEvent` 增加 `event=incoming_sms`
- Forwarder 兼容旧事件：`delivery_id` 且无 `call_id` 也视为短信

### 来电转发

旧去重键退化为固定 `":incoming"`，第二通来电起全部被跳过。

修复：

```
call_id + state + direction
```

### 未接来电

Android 事件新增 `missed`：

- 根据 `getConnectTimeMillis()` 判断是否真正接通
- 未接来电使用独立 `missedTemplate`
- 已接听后挂断不再误判为未接

### Bark V2

- 使用 `POST /push`
- `device_key`、`title`、`body`、`group`、`level=active`、`isArchive=1`
- 支持 `https://api.day.app/<key>` 或 `.../push` + Device Key
- 标题区分短信/来电/未接来电

### 飞书

- 解析 HTTP 200 响应体中的 `code/StatusCode`
- 支持签名 Secret：`timestamp + "\n" + secret` 的 HMAC-SHA256
- 当前实际阻断是飞书返回 `Bot Not Enabled`，属于飞书机器人未启用，不是代码

### 其他渠道

补充业务响应校验：

- 企业微信 `errcode`
- Slack / Telegram `ok`
- QQ `code`

## 5. CallKit / VoWLAN / 云端链路

- 显式云端模式只走 Relay，不再回退 VoWLAN。
- App 内接听使用 `IPhoneCloudCallSession.call`，不再误走本地。
- 云端 answer 先 HTTP early submit，不等待媒体 WebSocket。
- early answer 与确认复用同一命令 ID。
- CallKit 激活后禁止 `AVAudioSession.setActive(false)`；停止铃声使用 `deactivateSession:false`。
- Android owner-claim push 不再误结束已接听云端通话。
- VoWLAN 现在也启用 CallKit（`usesCallKit=true`）。
- 修复云端媒体 `CheckedContinuation` 重复 resume 闪退。
- Android 云端媒体重连指数退避（2/4/8/15 秒），避免打满 DO。
- 云端挂断不再走本地 VoWLAN。
- 云端自检分 6 步并可复制；健康检查 3 次重试。

## 6. Relay / APNs 现状

已确认不是普通 Cloudflare Worker 限额，而是：

```text
Exceeded allowed volume of requests in Durable Objects free tier
```

已部署的降级：

- 设备记录 DO 失败回退 KV
- 注册写 DO 失败至少写 KV
- 来电/短信 lifecycle、去重、Live Activity 尽力而为
- VoIP / Watch VoIP / 普通 alert 分开发送，VoIP 失败不吞掉 alert

最近部署版本：`c7a8448c-097a-44c3-9e27-b67925d99b67`。

仍需注意：

- DO 额度耗尽期间，媒体/call record 可能写不进去，CallKit 能响但接听媒体可能失败。
- 普通 alert 能显示，但 CallKit 不能由普通 alert 拉起。
- 用户从多任务划掉 App 后，iOS 不会因 VoIP Push 重新启动 App；这是系统限制。
- APNs 自身还有 sandbox/production、token、Apple 侧限制，不等于 Relay 正常就必达。

## 7. 验证与未验证

已执行：

- iOS `build-for-testing` 成功
- Android `test.sh` 全量通过
- Android Standalone 构建成功
- Relay `npm test`：62 项通过
- Relay `npm run check` 通过
- 多次真机覆盖安装 iPhone/Android

未完成：

- 所有转发渠道逐一端到端验收
- 飞书 Bot 启用后的真实投递
- 用户划掉 App 后普通来电 alert 完整验收
- DO 额度恢复后的完整云端通话验收
- 新 Release/TestFlight 发布

## 8. 关键文件

- [AirSIMSetupView.swift](../../iOS/AirSIM/AirSIMSetupView.swift)：通知转发配置模型与 UI（本轮追加在文件末尾）
- [VoIPPushController.swift](../../iOS/AirSIM/VoIPPushController.swift)：注册包、自检、Relay 健康重试
- [SamsungPairingClient.swift](../../iOS/AirSIM/SamsungPairingClient.swift)：配对配置传递
- [ForwardingConfigStore.java](../../android/phone-control-app/src/com/airsim/phonecontrol/ForwardingConfigStore.java)
- [NotificationForwarder.java](../../android/phone-control-app/src/com/airsim/phonecontrol/NotificationForwarder.java)
- [WireJson.java](../../android/phone-control-app/src/com/airsim/phonecontrol/WireJson.java)
- [AirSIMInCallService.java](../../android/phone-control-app/src/com/airsim/phonecontrol/AirSIMInCallService.java)
- [StandaloneAgentGateway.java](../../android/phone-control-app/src/com/airsim/phonecontrol/StandaloneAgentGateway.java)
- [push-relay-worker/src/index.mjs](../../push-relay-worker/src/index.mjs)
- [status-store.mjs](../../push-relay-worker/src/status-store.mjs)
- [cloud-pcm-resilience.md](../cloud-pcm-resilience.md)

## 9. 下一步

1. 先处理 Cloudflare Durable Objects 额度：等待重置或升级 Workers Paid；不要在耗尽时反复重连。
2. 飞书侧启用/重建自定义机器人，确认不再返回 `Bot Not Enabled`。
3. 用新短信、新来电分别测试 Bark/飞书/Discord/Slack/企业微信/Telegram/QQ/通用 Webhook。
4. 测试“Home/锁屏后台”和“多任务划掉”两种状态，记录 CallKit 与普通 alert 的差异。
5. DO 恢复后验证云端注册、心跳、接听、挂断、媒体。
6. 需要发布时重新构建并上传 TestFlight；当前工作区修复尚未进入新 Release。
