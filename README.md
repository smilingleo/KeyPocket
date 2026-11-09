# 钥匙口袋 · KeyPocket

An independent door-access client for iPhone, Apple Watch, and Android, using keys already authorized to an existing 钥匙宝 account.

钥匙口袋用于整理已有授权的门禁钥匙，通过蓝牙或声波发送开门请求。支持常用门、别名、排序，以及手机系统快捷入口。Apple Watch 可在同步账户后自行联网开门，无需 iPhone 在场。

**开始使用：[使用、构建与安装指南](docs/HOWTO.md)**

## 平台与状态

| 平台 | 版本与要求 | 已验证的范围 |
| --- | --- | --- |
| iPhone | 1.4（6）；iOS 17+ | 真机构建、签名、安装和启动；共享核心协议测试通过 |
| Apple Watch | 1.4（6）；watchOS 11+ | Series 11 / watchOS 27.2 真机安装和启动；实际开门待现场验证 |
| Android | 1.0；Android 8.0+，目标 API 36 | 核心协议测试、Android 15 模拟器检查；真实门禁待验证 |

手机和手表的蓝牙、声波效果取决于钥匙类型、接收设备和音频输出。界面显示“已发送”表示传输完成，请确认门的实际状态。

## 功能

- 使用已有账户，通过短信验证码登录并同步授权钥匙。
- 设置常用门、显示名称、顺序、蓝牙/声波方式及声波频段。
- 每次开门先向原服务刷新授权，使用服务器时间生成请求。
- iPhone 支持快捷指令；Android 支持桌面钥匙快捷方式和快捷设置磁贴。
- Apple Watch 从配对 iPhone 同步账户与配置，凭据保存于手表钥匙串，随后可独立联网使用。
- iPhone 提供不连接真实门禁的功能演示模式。

本机配置不能创建钥匙、扩大楼层权限或改变物业授权。远程云开门、二维码、次数访客钥匙和自动后台开门不在当前支持范围内。原服务仍负责账户及授权；本仓库不包含服务端。

## 快速开发

在仓库根目录执行。Apple 平台需要完整 Xcode；Android 需要 JDK、Python 3 和 Android SDK。

```sh
# Apple 平台的共享核心测试
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  swift test --package-path KeyPocket/Core

# 构建 iPhone + Watch 模拟器版本，不需要签名
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  xcodebuild -project KeyPocket/KeyPocket.xcodeproj -scheme KeyPocket \
  -configuration Debug -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath build/Simulator CODE_SIGNING_ALLOWED=NO build

# Android 核心测试与 APK 构建
bash KeyPocket-Android/scripts/test-core.sh
bash KeyPocket-Android/scripts/build-apk.sh
```

真机签名、自有开发者团队配置、手表配对和 APK 安装见 [HOWTO](docs/HOWTO.md)。仓库不提供可通用安装的签名包；本机生成的 IPA/APK、证书、私钥和描述文件不提交到 Git。

## 目录

```text
KeyPocket/                  iPhone 和 Apple Watch 的 Xcode 工程
  Core/                     Swift 协议、API、配置模型及测试
  KeyPocket/                iPhone 界面、蓝牙、声波和快捷指令
  KeyPocketWatch/           手表界面、独立授权刷新和声波输出
  Shared/                   WatchConnectivity 同步
  docs/                     实现、安装和验证记录
  AppStore/                 商店文案、截图及提交准备记录
KeyPocket-Android/          原生 Java Android 客户端、测试与构建脚本
KeyPocket-Support/dist/     静态支持页和隐私政策
```

## 文档

- [如何使用、构建、安装与续签](docs/HOWTO.md)
- [iPhone 项目](KeyPocket/README.md) · [Android 项目](KeyPocket-Android/README.md)
- [Apple Watch 实现及真机记录](KeyPocket/docs/APPLE_WATCH.md)
- [快捷指令与操作按钮](KeyPocket/docs/ICON_AND_SHORTCUTS.md)
- [声波与连接可靠性](KeyPocket/docs/SOUND_AND_RELIABILITY.md)
- [协议分析与兼容范围](KeyPocket/docs/ANALYSIS.md)
- [公开支持页](https://keypocket-support.smilingleo.chatgpt.site/support.html) · [隐私政策](https://keypocket-support.smilingleo.chatgpt.site/privacy.html)

## 数据与连接

iPhone 和 Watch 使用系统 Keychain 保存账户，Android 使用 Keystore 加密保存。账户同步和权限检查会连接原钥匙宝服务。兼容协议使用 HTTP 上的 AES 封装，并针对原服务设置网络例外；这不等同于 TLS 服务器身份认证。

真实开门需有效账户、对应门禁授权和网络连接。测试中的示例数据不能用于真实开门。此项目为独立兼容客户端，与官方钥匙宝及物业服务方无隶属关系。
