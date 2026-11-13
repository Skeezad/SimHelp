# VoWLAN 多客户端配对记录与地址迁移

更新：2026-10-23。解决旧实现只有一个 `secret_v1`，重新配对会覆盖其他 iPhone 凭据的问题；同时保留 Wi-Fi/VoWLAN 与 Tailscale 地址切换后的同一条配对记录。

## 旧实现的问题

- Android `VoWLANPairingStore` 只有全局 `secret_v1`。
- 第二台 iPhone 或一次重新配对会覆盖该 secret。
- 旧 iPhone 的 Keychain 仍保存旧 secret，能发现设备但 HMAC 失败，表现为“能连接、记录不匹配、无法配对”。
- iOS 只有按 Agent 的凭据，没有 pairing ID、地址历史和旧记录替换规则。

## Android 服务端

`VoWLANPairingStore` 现在保存 `records_v2`：

```text
id = SHA-256(client-generated VoWLAN secret)
created_at / last_seen
secret（应用私有 SharedPreferences，不写日志）
```

- 每次配对调用 `saveEncoded` **追加或刷新** 对应记录，不再覆盖其他客户端。
- 最多保留 16 条，按 `last_seen` 淘汰最旧记录。
- 旧 `secret_v1` 在首次读取时迁移为一条 legacy 记录；迁移标记保证不会被反复写回。
- 控制网关、PCM 网关和健康证明都通过 `match(...)` 找到签名对应的 secret；旧客户端和多个新客户端可同时验证。
- 单条记录损坏只跳过该条，不清空其他配对。
- 配对成功日志：`vowlan_pairing_client_saved clients=N`。

## iOS 客户端

`VoWLANPairingRecordStore` 保存：

```text
pairing id（secret 指纹）
agentID
deviceName
createdAt / lastSeenAt
endpoints[]（局域网/Tailscale 地址历史，最多 4 个）
```

secret 本身仍在 Keychain；UserDefaults 只保存指纹和地址历史。

- HMAC 验证通过后写入/刷新记录。
- 同一 Agent 重新配对（secret 轮换）会替换旧 pairing id，而不是留下两份“已配对”状态。
- 旧 pairing 的 endpoint 历史保留，切换到 Tailscale 或换端口后更新到同一条记录。
- 设置页“已配对设备”显示 pairing id 前 8 位和地址数量。

## 行为边界

- 单纯换地址且 secret 未轮换：不需要重新配对，健康检查成功后更新 endpoint。
- Android 重新配对生成新 secret：同一 iPhone 重新配对会替换本机记录；Android 端保留旧记录，其他 iPhone 不受影响。
- 旧版 iOS 使用 `secret_v1`：Android 迁移后仍接受，不强制升级。
- 目前没有逐客户端撤销 API；删除本机设备只清除 iOS 记录，Android 端记录仍在，需后续增加带认证的 revoke。
- 密码/Tailscale 路由仍受原有私有网段、HMAC、时间戳、nonce 和 replay 限制。

## 验证

- iOS：`testPairingRecordsFollowAgentWithoutDuplicatingAfterAddressChange` 覆盖同 Agent 换 secret、保留地址历史、多 Agent 删除。
- Android：全量 JVM/设备测试通过（含 Direct PCM、多 secret 控制路径编译）。
- 仍需真机验证：两台 iPhone 同时配对、Wi-Fi↔Tailscale 切换、旧版客户端升级、Android 重启和记录淘汰。
