# 三份音频日志的分流修复：候选 0.9.8.1（94）

> 另见：[Shizuku 13.6.0 在 HyperOS 3 上的 PCM 启动回归](shizuku-13.6.0-pcm-regression.md)。这是 Shizuku 上游问题，不是 AirSIM 0.9.8.9 的音频桥缺陷。

这是未发布的 Android Standalone／AVF Bridge 候选，不自动安装、提交推送或部署 Relay。保留 build 93 的臻情兼容修复，并补充 PCM 启动失败处理。iOS 已有的 0.9.8（92）音频图初始化顺序修正不在本轮重复修改。

## 必须区分的两类问题

两份可读原附件来自同一通臻情 Zhenqing／TYH123U Android 13 VoWLAN 电话：静音后 PCM 有字节但峰值一直为 1，解除静音后尾部累计峰值明显增大。见[臻情最低非零音量候选策略及声学验证限制](zhenqing-android13-call-audio.md)。94 保留该策略，不泛化到所有厂商。

用户补充的另一份文本实际来自 HUAWEI BLA-L29、Android 10、App 0.9.8（92）。其 VoBLE 启动媒体失败，随后 VoWLAN 也出现重复 `Connection reset`，收发字节始终为 0；没有成功进入远程 PCM 接管，不能归因为本次软件静音。默认电话角色查询命令曾被系统拒绝，但后续 `dialer_role=true` 且 Telecom 通话进入 active，因此它不是这份日志中已经接通却无音频的直接证据。

`pcm=running` 只表示特权桥进程存活／监听，不代表录音、蜂窝上行和 PCM READY 成功。华为系统究竟拒绝采集权限、缺少 Telephony Tx 设备、拒绝路由还是端点初始化失败，原 TXT 不足以确认。

## 已确认的代码缺陷与修复

1. 原来的采集端先创建，但资源保护范围从播放端创建成功后才开始。播放属性／路由探测／AudioTrack 构建失败会泄漏已创建的 AudioRecord，反复重试可能耗尽资源。现在每个端点创建后立即由独立 lease 管理；后续失败释放已有端点，stop 抛错仍执行 release，清理错误作为 suppressed evidence 保留，不覆盖原启动异常。
2. 原 TXT 只保留最后事件，紧随 `session_error` 的 `client_closed` 覆盖错误。现在保留最近失败的事件、阶段、稳定错误码、异常类别和有界失败计数；重试及“端点已创建”不清除失败，只有实际音频 `client_ready` 或桥进程重新初始化才清除。新的 `audio_initializing` 会清理旧通话音频统计，但保留待解决的失败。
3. 启动过程区分 buffer 查询、采集创建、播放属性、蜂窝上行路由、播放创建、路由绑定、端点校验、握手、采集启动、播放启动和发送 READY。设备查询拒绝／接口不可用不再当作“空设备列表”，保留有限层级的原始异常类型。发送 READY 失败明确标为 `handshake_write_failed`，不能误报采集失败。TXT 不采集任意 OEM 异常正文、地址、号码或 PCM；输出白名单标签和异常类别。原错误对象仍保留在内存 cause／suppressed 链，不作为未脱敏文本导出。

以下字段会穿过 Shizuku 状态快照保留到导出的 TXT：

```text
pcm_failure=session_error
pcm_error_phase=create_capture
pcm_error_code=permission_denied
pcm_error_class=SecurityException
pcm_failure_count=1
```

这只是格式示例，不是对华为实际异常的推断。`telephony_tx_unavailable`／`telephony_tx_rejected` 表示缺少／拒绝蜂窝上行路由；`capture_*`／`playback_*` 表示对应端点创建、初始化或启动失败。

不通过开启环境麦克风、退回扬声器、强行换源、重启系统音频或自动挂断来掩盖系统不支持。没有新增云端请求或重试循环；音频 READY 仍必须等待实际端点启动，不能把 TCP 连接当成双向通话成功。版本提升到 94 确保覆盖升级后 Shizuku helper 采用本轮实现。

## 回归与真机边界

新增失败测试先在旧实现下观察到两个预期断言失败：实际生产启动路径泄漏采集资源，以及关闭事件丢失原始失败。随后又在故障注入中观察到权限查询被误标为空路由，以及 READY 写失败被误标为采集失败，两项均补测试后修正。资源测试只替换 Android 分配／查询边界，运行真实 `PhoneAudioBridge.streamCallAudio`，四次属性／路由初始化失败均检查采集释放；再让有效 HELLO、采集与播放成功启动，注入 READY 输出失败，检查两个端点释放、错误分类及未发布 client_ready。其他用例覆盖清理异常不遮蔽原异常、释放顺序、重复释放保护、失败跨重试保留、真实 READY 后清除、隐私字段过滤，以及最终 Watchdog TXT 字段传递。

构建和 JVM 回归不证明问题华为设备已经有双向声音。需保留数据覆盖正式签名候选包，在问题设备做一通电话，再导出音频 Watchdog TXT。若仍失败，新字段应能把泛化的 `Connection reset` 收敛到具体权限／路由／初始化阶段。无法凭现有日志承诺该系统开放蜂窝音频能力。

最终验证：`sh android-standalone/test.sh` 在最后一次 READY 阶段修正后完整重跑，退出码 0。包含 PCM 桥 64 项检查、真实启动路径的四次属性／路由失败及 READY 写失败注入、18 组通话音频生命周期、API 29–35 兼容、静音策略与恢复、VoBLE 网关生命周期及归属拨号测试。首次全量曾被新增的权限查询误分类回归拦下，修正后重跑通过；后续审查指出的 READY 阶段误分类也已先观察失败、后修复并纳入最终全量。构建仍有 API 弃用和资源 lease 哨兵未在 try 正文引用的编译提示，无编译错误。只读复核无剩余 Critical／Important／Minor。

已构建正式证书签名的 Standalone 候选包（未正式发布）：`android-standalone/build/candidate-0.9.8.1-94/AirSIM-Android-Standalone-0.9.8.1-94-release.apk`。Manifest 为 `0.9.8.1 (94)`、最低 API 29、目标 API 35、`debuggable=false`；APK v3 签名校验通过，证书与既有正式包一致，可覆盖同证书安装而保留数据。文件 SHA-256：`9bb6a7f5af2a7aaeec31c0609a25ced181e9a6659f40ded361e393911ac80f89`。未安装、未提交推送、未发布 Release、未部署 Relay；现有 iOS 后台状态修复工作不在本轮重复修改。
