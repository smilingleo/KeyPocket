# 声波协议与多次点击问题 — 1.1 / build 3

## 已确认的范围

输入仍是用户提供的 Android APK 4.5.0。用户尚未确认问题发生时的耳机播放/通话状态；未取得 iPhone 官方 App 的可分析二进制，也没有失败当时的音频路由或门禁运行记录。因此，以下可确认 Android 版的实现，并提出对应风险，不能证明用户的 iPhone 官方版具有相同代码或已经找到现场故障的唯一原因。

原 APK：SHA-256 `575343454ffde12921b1a78fb6cc9d192e25d68c139f67ceb0d8d9b08aceda95`。
原声波库 `lib/arm64-v8a/libvoiceRecog.so`：SHA-256 `883bd0e942423ebc81f577d0a017be41603f10af7ba7d6da26c3f3e08fc68e22`。

## 静态观察及推断

源码路径均相对于开发机的 `../yaoshibao-research/decompiled/sources/`。

| 观察 | 来源 | 对失败的解释边界 |
| --- | --- | --- |
| 耳机或 A2DP 已连接时设置音频模式、扬声器状态，固定等待 2000ms 后发声；未在发送前检查最终输出端口 | `com/bluelight/elevatorguard/service/ElevatorPlayer.java`: `autoSetAudioVolumnAndMode`, `play`, `lambda$play$1` | 固定延时可能不能覆盖所有路由切换时序；Android 证据，不是 iOS 现场证明 |
| 无录音权限/关闭噪声检测时随机选三个可用频段之一；噪声检测分支也有随机选择 | 同类 `playSelect` | 若接收器、环境或手机对某频段不理想，多次点击可能碰巧换到可用频段；尚无现场频谱证明 |
| 先尝试 BLE，部分失败再回退声波；Android GATT 错误及断连会重连 | `common/v.java`: receiver `d`, `E`; `service/BleService.java`: `AnonymousClass5` | “蓝牙连接耳机”和“蓝牙门禁连接失败”不是同一个证据，不能据此断定两者存在因果关系 |
| 声波码包括秒内信息、分钟信息及校验，时间由服务器偏差修正 | `common/k.java`: `a`; `common/utils/o.java`: `F`; `p1/c.java`, `p1/g.java` | 路由切换后才生成授权码，可减少等待造成的时效损耗；现场是否因此失败未知 |

Apple 文档确认，显式 speaker override 适用于 playAndRecord，能够把输出切到内置扬声器；defaultToSpeaker 本身不等同于强制覆盖耳机。见 [Apple speaker override](https://developer.apple.com/documentation/avfaudio/avaudiosession/overrideoutputaudioport(_:))、[Apple QA1754](https://developer.apple.com/library/archive/qa/qa1754/_index.html)。

## 声波协议恢复与独立验证

REA 的 native provider 初次报告缺少 Ghidra；未修改 MCP 注册或重启用户会话。随后在研究目录中使用官方 Ghidra 12.1 压缩包，针对 arm64 Mac 从随附源码构建 decompiler，再用独立 headless 脚本分析 ELF。反编译输出保存在 `../yaoshibao-research/native/voice-decompiled.c`；它不是 REA MCP 返回的 Evidence。原生宿主进程没有加载 Android 库。

主要 ELF 符号地址（Ghidra 载入基址额外加 0x100000）：

- `vpp_convertTextToCodes`: `0x1ac44`，十六进制字符转符号、CRC、纠错、重复符号替换。
- `vpp_realRSEncode`: `0x1a8c8`，RS(15,13)，GF(16)。
- `calc_step_crc16`: `0x18040`，以每个半字节值作为一个字节更新 CRC-CCITT，初值 0xffff。
- `encode_rs`: `0xf9b8`，反向处理 13 个数据符号，再附加两个校验符号。
- `enc_encode3`: `0xcad0`，首部静音 10ms，符号各 65ms，尾部静音 100ms。
- `slg_gen`: `0xc320`，44.1kHz、16bit 单声道、正弦载波、幅度包络。
- Java `ElevatorPlayer.onBind` 提供起始频率 9000 / 12200 / 17000Hz，并引用 `TbsListener.ErrorCode.STARTDOWNLOAD_API_LEVEL_BELOW_FROYO`。该常量实际为 **150**，所以 App 覆盖 SDK 默认频率表后使用 **150Hz 步进**，不是原生库默认的 200Hz 步进。

使用 Unicorn 对原 APK 的 AArch64 数学编码函数进行受控仿真执行：映射 ELF 和重定位，提供私有内存分配、字符串、数学和 PCM 缓冲回调；不实现网络、文件或真实音频输出。未知导入会立即终止。测试输入全部是合成的九位十六进制字符串。脚本、哈希和符号夹具保存在 `../yaoshibao-research/native/`。

Swift 实现与原生库仿真结果比较：

- 5 组符号序列一致，包含连续重复值和纠错符号。
- 3 组频段 PCM **逐字节相同**。每组夹具 112878 字节。
- 标准频段夹具 `012345678` 的 SHA-256：`24288fc2c682319e1ca7421531eb3f70a5d7c4dee0ed7fc7208e90122742aacd`。
- 低频夹具：`127fe1a29de9b2cda6a9bb2f60409889063fef9546c00f61d3ee7a1168c420a0`。
- 高频夹具：`28e9a878165c7306ed533db234a3d6dc5958c19507f91cc260f18a8323d0226a`。
- 授权字符串与独立编译的原 Java `o.F`、TEA 和 CRC 方法一致，时间固定、授权编号为合成值。

仿真只证明数学与格式兼容，不证明 iPhone 扬声器的频响、实际路由、门禁固件或现场开门成功率。

## 新 App 的改动

1. 每扇门单独选择蓝牙或声波；已恢复的声波仅支持原流程允许的类型 0、3、100。组合钥匙、次数访客钥匙、类型 6/7 等保持原来的限制。
2. 声波固定从内置扬声器发送。显式覆盖路由后，要求输出端口持续 200ms 都是内置扬声器；最多等待 3 秒。等待失败就不发信号。发送中路由改变或音频中断即停止，提示确认门的实际状态。
3. 路由就绪后才生成短时授权码。应用仅播放生成音频，没有录音器、输入节点、录音保存或上传逻辑。Apple 的扬声器覆盖要求使用 playAndRecord 类别；Info.plist 含该音频通道用途说明，但代码不主动请求录音权限。
4. 每扇门固定标准、低频兼容或高频，取消随机选频。默认标准。媒体音量低于 40% 时提示用户调整，不用代码突然拉高系统音量。
5. 播放后解除覆盖、释放自己的音频会话并通知其他音频恢复。其他 App 是否自动续播由系统和对应 App 决定。没有断开/重置整个蓝牙适配器。
6. BLE 只在尚未写出任何开门数据时，对暂时连接失败自动重试一次。数据一旦开始写出就不自动重发。全部写入 ACK 后立即断开可正常报告“已发送”，而不是误报连接失败。发送完成仍不等于物理门已解锁。
7. 旧常用门、名称和顺序可迁移；新字段缺省为原来的蓝牙方式，不会升级后自动改成声波。

## 验证及待测

- 18 项 XCTest 全部通过，包括授权字节、三频段原生 PCM 夹具、CRC/纠错、权限失效拒绝、旧设置迁移。
- Xcode 27.2 / iOS 27.2 SDK 签名构建成功；1.1 / build 3 已覆盖安装到用户的 iPhone。
- 没有在开发过程中发送真实声波或点击真实开门按钮。
- **仍需用户现场测试**：耳机断开；耳机已连接但未播放；耳机连接并播放音乐。分别观察路由提示、首次点击是否打开以及音乐行为。用户报告的原 App 问题目前属于有依据的候选解释，尚未完成因果验证。
