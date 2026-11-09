# 钥匙口袋 · KeyPocket 1.2

iPhone 门禁客户端原型，使用现有钥匙宝账户授权的门禁。iOS 17+，SwiftUI / CoreBluetooth / AVAudioSession，协议编码为 Swift 实现，不依赖 Android SDK 或第三方运行库。

目前支持：短信登录、登录后单独同步钥匙、常用门与本机别名/排序、已恢复的蓝牙协议、部分钥匙类型的声波开门。账户令牌保存在本机 Keychain，开门前刷新授权。

新增深绿色钥匙图标，以及可选择常用钥匙的系统快捷指令动作。设置操作按钮或多功能菜单请参阅 [配置步骤](docs/ICON_AND_SHORTCUTS.md)。

## 使用

1. 打开手机上的 **钥匙口袋**，登录并同步钥匙。
2. **配置 → 选择门 → 开门方式**，选择蓝牙或声波。原有配置升级后保持蓝牙。
3. 声波可选标准、低频兼容或高频。默认标准；若某扇门接收不稳定，再为它调整频段。
4. 到门边点击打开。声波会暂时打断其他音频，确认输出为手机扬声器后才发送；媒体音量低于 40% 时会提示调整。
5. “已发送”表示传输完成，请确认门的实际状态。

声波数学编码已与原 APK 原生库的受控仿真输出逐字节核对，但实际门禁和耳机路由仍需现场验证。详见 [声波与可靠性分析](docs/SOUND_AND_RELIABILITY.md)。

## 安装与签名

当前签名包：`../KeyPocket-iPhone-1.2.ipa`。它只适用于嵌入描述文件覆盖的设备。用户 iPhone 已安装此版本；开发签名到期后需要重新构建安装。首次安装可在 iPhone 的 设置 → 通用 → VPN 与设备管理 中信任开发者，并开启开发者模式。

源项目：`KeyPocket.xcodeproj`。Xcode 27.2 已安装，项目选择了用户的 Personal Team。连接并解锁手机后可通过 Xcode Run 重建安装。

## 开发与验证

```sh
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
swift test --package-path Core
xcodebuild -project KeyPocket.xcodeproj -scheme KeyPocket \
  -configuration Debug -destination 'generic/platform=iOS' \
  -derivedDataPath build/SignedData -allowProvisioningUpdates build
```

18 项 XCTest 已通过。测试只使用合成数据及本地 HTTP stub，不发送真实验证码、登录或开门请求。只有 Command Line Tools 的环境可使用 `python3 scripts/verify.py` 运行同一组核心测试。

```sh
./scripts/package-signed-app.sh /absolute/path/to/KeyPocket.app /absolute/path/to/KeyPocket-iPhone.ipa
```

此脚本要求已签名的设备 App 和嵌入的 provisioning profile；不会把模拟器包或未签名构建当作可安装 IPA。

## 兼容边界

- BLE FFC0/FFC1/FFC2/FFC3 central 模式；类型 0、3、5、6、7、100 的包生成已恢复。类型 6/7 有服务器二次验证；可选电量通知未实现。
- 声波类型 0、3、100，单门/单层或大门授权。原 APK 的组合钥匙、次数访客钥匙等声波路径不在支持范围内。
- FFE peripheral/server 模式、二维码、次数访客钥匙、远程云开门和自动后台开门未实现。
- 每扇门配置只改变本机名称、常用顺序和传输方式，不能自行添加门编号、楼层权限或改变物业授权。
- 原服务使用 HTTP 上的 AES 封装；仅对观察到的服务域名保留 HTTP 兼容例外。它不等于 TLS 身份认证。

更多来源和历史验证记录见 [ANALYSIS.md](docs/ANALYSIS.md)。构建、测试、安装和启动日志位于 `build/`，不包含在源码压缩包中。
