# 钥匙口袋 · iPhone 与 Apple Watch 1.4（6）

SwiftUI 原生客户端，使用已有钥匙宝账户授权的门禁。iPhone 支持蓝牙、部分钥匙类型的声波、常用门配置、快捷指令和功能演示；Watch 从配对手机同步账户后，可自行联网检查授权并发送请求。

- iPhone：iOS 17+，SwiftUI / CoreBluetooth / AVAudioSession。
- Apple Watch：watchOS 11+；Series 11 / watchOS 27.2 真机已完成安装及启动，真实开门仍需现场验证。
- 共享核心：Swift Package，18 项协议/API/音频编码测试此前通过。

## 开始使用

完整步骤见仓库级 [使用、构建与安装指南](../docs/HOWTO.md)，包括账号登录、手表同步、真机签名、描述文件到期续签、命令行安装和故障排查。签名团队和 Bundle ID 需按自己的账号配置。

在本目录执行核心测试：

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --package-path Core
```

模拟器构建：

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  xcodebuild -project KeyPocket.xcodeproj -scheme KeyPocket \
  -configuration Debug -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath build/Simulator CODE_SIGNING_ALLOWED=NO build
```

## 兼容范围

- BLE FFC0/FFC1/FFC2/FFC3 central 模式，支持类型 0、3、5、6、7、100；类型 6/7 需要服务器二次验证。
- 声波支持类型 0、3、100；编码与受控样例核对，真实接收效果需现场验证。
- 未实现 FFE peripheral/server 模式、二维码、次数访客钥匙、远程云开门和自动后台开门。
- 每次开门前刷新服务端授权。本机配置只能改变名称、常用顺序和传输方式，不能添加或扩大权限。

## 实现与记录

- [Apple Watch](docs/APPLE_WATCH.md)
- [个人安装与续签](docs/PERSONAL_INSTALL.md)
- [操作按钮及快捷指令](docs/ICON_AND_SHORTCUTS.md)
- [声波与可靠性](docs/SOUND_AND_RELIABILITY.md)
- [协议分析](docs/ANALYSIS.md)

`build/` 是本机日志和产物目录，不提交到 Git。仓库不包含通用签名安装包；商店提交材料不代表应用已上架。
