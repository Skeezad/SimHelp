# 臻情 Android 13 通话下行近乎静音：候选修复

Android Standalone／Bridge 候选版本 `0.9.8.1 (93)`，尚未发布，尚未在报告问题的臻情设备上验收。iOS、Relay、PCM 格式、采样率及麦克风策略不变。

## 日志证据与判断边界

可读取的两份日志来自同一通 VoWLAN 电话：`manufacturer=Zhenqing`、`model=TYH123U`、API 33、App `0.9.8 (92)`。另一份附件受本机访问权限限制，尚未读取。

音频接管后，旧版执行 `policy=mute`，系统回读 `muted=true volume=0`。此后多次采样中，下行累计字节持续增加，但 PCM16 峰值一直只有 `1`；上行也持续有数据。解除静音后的结束记录中，下行累计峰值增至 `6280`。

这强烈提示该机的通话输出静音会连带压低 `VOICE_DOWNLINK` 采集，但不是厂商 HAL 原理的已验证结论：没有这台真机的静音前后 A/B 录测，也没有对应 iOS 播放日志。`pcm_route=verified` 仅说明蜂窝上行路由验证，不证明下行声音可听；字节增长不等于有效语音。

## 修复策略

- 仅对 `Build.MANUFACTURER=Zhenqing`（忽略大小写和前后空白）使用 `minimum_nonzero_volume`，不泛化到所有紫光展锐或 Android 13 设备。
- 在已有的唯一远程通话／就绪 PCM 归属条件下，保留通话流未静音，音量取 `max(1, 系统最低档)`，不修改 PCM 增益，不改用环境麦克风代替蜂窝音频。
- 先保存原音量与静音位，操作后同时回读音量和未静音状态；失败回滚，挂断、媒体断开时恢复原状态，服务销毁时尽力恢复。原本已静音时，仅接管期间临时取消输出静音，恢复时最后写回原静音位。恢复失败会记录日志；常驻服务保留快照供重试，但服务销毁后不能保证继续重试。
- Watchdog 对该策略同时验证非零最低档和未静音，不能把未静音误修复成静音。原来的 3 次预算、15 秒冷却及通话归属检查不变。不会因安静片段自动重启或改变策略。
- 三星保留原系统最低档策略，其他厂商保留原行为。最低非零档可能仍有本机声音，不能保证物理听筒完全静音。
- TXT 将累计 PCM16 峰值 `0` 标为 `all_zero`、`1` 标为 `near_zero`。更大峰值只标为 `observed`，不宣称 iOS 播放或双向语音已验证。

版本号提升到 93，使已授权的 Shizuku UserService 在覆盖升级后采用新的实现，而不复用 build 92 的常驻服务。正式签名候选 APK 可保留数据覆盖原正式包；不同证书调试包不能混装覆盖，不要卸载清数据。

## 验收

JVM 回归覆盖零／非零系统最低档、原来已静音、重复接管、音量及静音漂移、OEM 忽略写入、失败回滚、恢复重试、三星及其他厂商行为不变，以及实际控制器参与的 Watchdog 修复。构建／模拟边界测试不能代替声学验收。

本地已运行 `sh android-standalone/test.sh`，退出码 0，包含 API 29–35 短信兼容、旧 API 检查、18 组通话静音生命周期、PCM 集成、网关生命周期和拨号归属测试。新回归先在旧行为下出现 3 个预期断言失败，修正后通过。构建有已有 Android API 弃用及 JDK 工具链提示，无编译错误。只读审查无 Critical／Important 问题；已补充服务销毁恢复为尽力而为的说明。

已构建正式证书签名的 Standalone 候选包（非正式发布），版本 `0.9.8.1 (93)`、`debuggable=false`，签名验证通过且与既有正式包证书 SHA-256 一致。产物位于 `android-standalone/build/candidate-0.9.8.1-93/AirSIM-Android-Standalone-0.9.8.1-93-release.apk`，文件 SHA-256：`6bee2e64150e77e0ce06c274a2efbb4af535f39dfc94efaa8e8c47d419aefedf`。未安装、未提交推送、未发布 Release，未部署 Relay。

需要问题设备覆盖安装后再进行实际通话：接听后确认 iPhone 双向语音、本机最低音量、挂断恢复；分别复测 VoWLAN 和实际使用的其他模式。导出的新 TXT 应显示 `output_policy=minimum_nonzero_volume`、`minimum_volume>=1`、`muted=false`。若持续 `near_zero`／无声，继续采集日志，不以音量已回读成功作为问题解决证据。

Android 官方 [AudioManager 接口](https://developer.android.com/reference/android/media/AudioManager)区分通话流音量与静音操作；[Audio HAL 文档](https://source.android.com/docs/core/audio/implement)说明厂商负责底层实现，但没有承诺所有设备的下行采集与音量控制互相独立。
