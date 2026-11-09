# Apple Watch 版本 1.4（6）

目标设备：用户 Apple Watch Series 11 / watchOS 26.6。最低 watchOS 11。

## 使用

1. 安装包含 KeyPocketWatch 的 iPhone 版本和配对手表版本。
2. iPhone 登录并刷新钥匙，在配置中设好常用门、名称、顺序、蓝牙或声波、频段。
3. 点击「同步到 Apple Watch」，在手表打开钥匙口袋等待同步。
4. 手表可以在 iPhone 不在场时自行联网检查最新授权并发送蓝牙或声波请求。需要手表的 Wi-Fi 或蜂窝网络，不支持完全离线授权。
5. 配置改变后需要再次主动同步；账户失效时返回手机重新登录同步。

## 行为与限制

- 账户通过系统 WatchConnectivity 的最新应用上下文同步，只发送账户和偏好，不同步缓存门禁授权列表。账户凭据保存于手表 Keychain。
- 手表每次开门先请求服务器授权；不使用离线缓存规避权限变更。
- BLE 复用 iPhone 客户端，保留仅在尚未发出开门数据时重试一次的规则。
- 声波使用相同协议编码；仅允许内置扬声器，音量至少 40%，不向耳机发送。S11 的扬声器频响和门禁接收效果仍需真机验证。
- 音频中断、取消、进入后台会停止操作。请求发送不等于门已解锁。
- 手机退出登录后的手表清除请求依赖下一次配对连接送达；可在手表本地「移除手表账户」。
- 原服务可能限制多设备/会话，或在刷新时轮换 token；手机与手表共用会话是否持续有效需实际账户验证，未改造或绕过原服务授权。
- 真机需注册手表设备并重新导出包含手表的个人签名包。到期时间以新包内手机与手表描述文件为准。

## 验证

手表模拟器构建与手机/手表组合模拟器构建通过。共享协议测试 18 项通过。真实账户同步、脱离手机联网、蓝牙门禁、手表声波仍需 S11 真机测试，未宣称已开门。

## 当前安装进度与发现阻塞

iPhone 1.4（6）已覆盖安装并成功启动；真实 S11 仍未被 Xcode/Device Hub 发现。附近配对窗口、同 Wi-Fi、手机/手表重连未解决。

Mac 日志持续出现 `kAMDMuxCreateListenerError`、`USBMuxIntNewSocket connect failed: 2 - No such file or directory`。`system/com.apple.usbmuxd` 显示运行，但 `/var/run/usbmuxd` 不存在。watchOS DDI 显示 usable。该通信异常是待修复线索，尚不能认定为全部根因。

已重启用户级 AMPDeviceDiscoveryAgent，错误仍存在。尝试用 `sudo -n launchctl kickstart -k system/com.apple.usbmuxd` 被管理员密码要求阻止，没有修改系统服务。下一步让用户重启 Mac 后重新检查接口及设备发现。不要要求用户重置手表或解除与 iPhone 的正常配对。

当前 iPhone 开发签名描述文件到期为 2027-11-04 06:58:50 UTC；手表构建的描述文件到期为 2027-11-04 08:01:41 UTC，未完成真实手表安装。旧 Ad Hoc 1.3 备份仍在 Downloads。

## 2026-11-09 恢复手表安装

用户已将真实 S11 升级至 watchOS 27.2，并开启开发者模式，授权继续手表 App。新工程位置为 `<workspace>/KeyPocket`。

Xcode 当前已能识别「Leo的S11」，UDID `<REGISTERED_WATCH_UDID>`，显示已配对；设备信息明确显示 Developer Mode Enabled。此前“未发现手表、无开发者模式”的阻塞已解决，不再降级 Xcode 或重复处理旧 USB 异常。

当前尚未完成安装：手表被发现但网络连接未建立，iPhone 显示未连接。已请用户保持手表解锁并与 Mac 同 Wi-Fi、手机用数据线连接并解锁，再继续签名注册与安装。实际签名有效期将在新包生成后核对。

本次通用 watchOS 真机包已重新构建成功，位置 `build/S11DeviceData/Build/Products/Release-watchos/KeyPocketWatch.app`。实际检查发现嵌入描述文件仍未包含真实 S11 的 UDID，不能把该包视为已可安装。定向设备构建在建立网络连接时超时；Device Hub 为 Connecting display。Apple Developer 设备列表网页会话已过期，未进行设备注册或修改账户。先待用户完成设备就绪，再通过 Xcode 自动注册并重新签名；如需网页登录再提出。

## 2026-11-09 真机安装成功

设备就绪后，真实 S11 与 iPhone 均显示 connected。定向 S11 构建成功，Xcode 自动注册设备，并生成确实包含 `<REGISTERED_WATCH_UDID>` 的描述文件。手表描述文件到期时间为 2027-11-09 00:08:06 UTC（北京时间 08:08:06）。

`devicectl device install app` 已确认成功安装 `net.smilingleo.KeyPocket.watchkitapp`。后续需要用户在 iPhone 配置页主动同步到账户/常用门配置，并验证手表联网刷新及真实门禁。安装过程没有发送真实开门请求。

启动验证：`devicectl device process launch` 成功启动手表 App。账户和钥匙尚待用户在 iPhone 的「配置 → 同步到 Apple Watch」主动同步。没有代用户执行真实开门。

iPhone 配套版本也已重新构建并覆盖安装（Bundle ID 不变），其嵌入的 Watch App 签名已包含真实 S11。配套 IPA 备份为上级目录 `KeyPocket-iPhone-Watch-1.4.ipa`，codesign 与 ZIP 完整性检查通过。iPhone 描述文件到期仍为 2027-11-04 06:58:50 UTC，手表为 2027-11-09 00:08:06 UTC；应在较早日期前一并续签。
