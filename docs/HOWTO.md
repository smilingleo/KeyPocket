# How to · 使用、构建与安装

下列命令均从仓库根目录运行；Xcode 图形界面打开 `KeyPocket/KeyPocket.xcodeproj`。命令中的设备 ID 和团队 ID 必须替换为自己的值。

## 1. iPhone 日常使用

1. 打开钥匙口袋，阅读数据说明和原服务条款后，用已有账户的手机号及验证码登录。
2. 等待钥匙同步。如果没有钥匙，在原服务或物业确认授权，再刷新；本 App 不能在本地补发权限。
3. 进入「配置」，选择门，设置名称、常用状态和顺序。
4. 按门禁实际支持的方式选择蓝牙或声波。声波可以按门设置标准、低频兼容或高频。
5. 靠近对应门禁，在「开门」页点击按钮，确认门的实际状态。

首次蓝牙开门需要系统权限。iPhone 声波会尝试切换至本机扬声器，并要求媒体音量至少 40%；若通话、耳机路由或其他音频中断阻止输出，会停止并提示。不要把传输完成当作门锁反馈。

尚未登录时可使用「查看功能演示」，它只显示示例钥匙，不扫描蓝牙、不发声波，也不请求真实账户服务。

### 快捷指令与操作按钮

先把门设为常用，再到系统「快捷指令」添加钥匙口袋的「打开常用门」动作并选择钥匙。支持操作按钮的 iPhone 可以在「设置 → 操作按钮 → 快捷指令」中选择该指令。完整步骤见 [快捷入口文档](../KeyPocket/docs/ICON_AND_SHORTCUTS.md)。

## 2. Apple Watch 使用

1. 安装配套的 iPhone 和 Watch App，先在 iPhone 登录并配置常用门。
2. iPhone 的「配置 → 同步到 Apple Watch」会主动发送账户及常用门配置；只同步到自己的配对手表。
3. 在手表打开钥匙口袋，等待钥匙刷新。
4. 靠近门禁，点击常用门；手表自行检查最新授权并通过蓝牙或扬声器发送请求。

**不带手机可以使用，但手表必须能联网。** 可使用 Wi-Fi 或具备相应能力与服务的蜂窝网络；当前不支持完全离线授权。

声波仅允许从手表内置扬声器输出，音量至少 40%。其他音频设备被选中时需先切回扬声器。真实接收效果仍需按门禁现场验证。

修改手机上的常用门配置后，再点一次同步。账户失效时，在 iPhone 重新登录并同步。手机退出登录的清除请求需在下次手表连接时送达；也可直接在手表「移除手表账户」。

## 3. Apple 真机开发与安装

### 准备签名

- 在 Xcode 的 Apple Accounts 中登录自己的 Apple Developer 账号。
- 免费 Personal Team 的设备描述文件通常只有 7 天有效；本项目个人长期使用采用付费开发者团队签名，实际到期时间以生成的描述文件为准。
- 连接并解锁 iPhone，按提示信任 Mac。
- Watch 保持解锁，连接可与 Mac 通信的 Wi-Fi，在 Device Hub 完成开发配对。手机、手表均需开启开发者模式；它不是系统测试版开关。
- Xcode 工程默认带有本项目的团队和 Bundle ID。其他开发者应在两端 Signing & Capabilities 改成自己的团队和唯一标识，并把 `KeyPocketWatch/Info.plist` 中的 `WKCompanionAppBundleIdentifier` 改为对应的 iPhone 标识。手表标识通常使用 iPhone 标识加 `.watchkitapp`。

Apple 参考：[开发者模式](https://developer.apple.com/documentation/xcode/enabling-developer-mode-on-a-device)、[设备配对](https://developer.apple.com/documentation/xcode/pairing-your-devices-with-your-mac)。

### 使用 Xcode 安装

1. 打开工程，选择 `KeyPocket` scheme 和自己的 iPhone，点击 Run。
2. 选择 `KeyPocketWatch` scheme 和真实 Apple Watch，点击 Run。
3. 按 Xcode 提示完成设备注册及签名。首次准备设备或复制调试符号可能需要时间。
4. 按第 2 节同步账户，在实际门禁旁验证。安装和启动成功并不代表真实门禁已经验证。

### 使用命令行安装

```sh
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
xcrun devicectl list devices

# 替换 YOUR_IPHONE_UDID 和 YOUR_TEAM_ID
xcodebuild -project KeyPocket/KeyPocket.xcodeproj -scheme KeyPocket \
  -configuration Release -destination 'id=YOUR_IPHONE_UDID' \
  -derivedDataPath build/PhoneDevice DEVELOPMENT_TEAM=YOUR_TEAM_ID \
  -allowProvisioningUpdates -allowProvisioningDeviceRegistration build

xcrun devicectl device install app --device YOUR_IPHONE_UDID \
  build/PhoneDevice/Build/Products/Release-iphoneos/KeyPocket.app

# 手表需要独立注册到签名团队
xcodebuild -project KeyPocket/KeyPocket.xcodeproj -scheme KeyPocketWatch \
  -configuration Release -destination 'id=YOUR_WATCH_UDID' \
  -derivedDataPath build/WatchDevice DEVELOPMENT_TEAM=YOUR_TEAM_ID \
  -allowProvisioningUpdates -allowProvisioningDeviceRegistration build

xcrun devicectl device install app --device YOUR_WATCH_UDID \
  build/WatchDevice/Build/Products/Release-watchos/KeyPocketWatch.app

xcrun devicectl device process launch --device YOUR_WATCH_UDID \
  YOUR_WATCH_BUNDLE_ID
```

如使用其他 Bundle ID，先完成上述工程配置修改。`YOUR_WATCH_BUNDLE_ID` 是手表 target 的实际标识。

### 备份 IPA 与续签

设备构建完成后，可打包包含配套 Watch App 的已签名 iPhone App：

```sh
bash KeyPocket/scripts/package-signed-app.sh \
  "$PWD/build/PhoneDevice/Build/Products/Release-iphoneos/KeyPocket.app" \
  "$PWD/build/KeyPocket-iPhone-Watch.ipa"
```

该脚本检查签名并生成 IPA，不会重新签名或扩大可安装设备范围。手机包内的 Watch 描述文件也必须包含目标手表；若新增注册设备，应重新构建整个手机配套包再备份。

描述文件到期后通常无法启动 App。到期前使用仍有效的开发者账号重新生成签名并覆盖安装，保持相同团队和 Bundle ID，不先卸载，以尽量保留账户及设置。当前个人安装到期记录见 [个人安装](../KeyPocket/docs/PERSONAL_INSTALL.md) 与 [Watch 记录](../KeyPocket/docs/APPLE_WATCH.md)。仓库未配置自动续签。

付费开发签名或 Ad Hoc 安装无需公开上架 App Store，但仍需开发者模式。TestFlight 和 App Store 属于其他分发方式，不是本指南的安装路径。

## 4. Android 构建与使用

准备 JDK 17+、Python 3、zip、Android SDK Platform 36 和 Build Tools 36.0.0。默认 SDK 位置为 `~/Library/Android/sdk`；其他位置设置 `ANDROID_SDK_ROOT`。

```sh
bash KeyPocket-Android/scripts/build-apk.sh
# 输出 KeyPocket-Android/build/KeyPocket-Android-1.0.apk

# 只在你明确选定的设备安装；替换 ANDROID_DEVICE_SERIAL
adb devices
adb -s ANDROID_DEVICE_SERIAL install -r \
  KeyPocket-Android/build/KeyPocket-Android-1.0.apk
```

也可以把自己构建的 APK 传到手机，按系统提示允许该来源安装。构建脚本默认使用本机 `~/.android/debug.keystore`；覆盖升级需保留同一签名密钥。该默认开发证书不应当作公开发行密钥。

登录、设置常用门及开门方式后即可使用。Android 12+ 需要附近设备权限；Android 8–11 的蓝牙扫描需要定位权限和系统定位开关，App 不读取 GPS 坐标。声音需从内置扬声器输出，媒体音量至少 40%。

单门桌面快捷方式、长按图标快捷菜单和快捷设置磁贴的配置见 [Android README](../KeyPocket-Android/README.md)。

## 5. 测试与模拟器构建

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  swift test --package-path KeyPocket/Core

DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  xcodebuild -project KeyPocket/KeyPocket.xcodeproj -scheme KeyPocketWatch \
  -configuration Debug -destination 'generic/platform=watchOS Simulator' \
  -derivedDataPath build/WatchSimulator CODE_SIGNING_ALLOWED=NO build

bash KeyPocket-Android/scripts/test-core.sh
```

Android 核心测试会从 Maven Central 下载测试专用的 `org.json` JAR。Android 模拟器运行检查使用 `bash KeyPocket-Android/scripts/test-device.sh`，仅用于没有真实账户的测试模拟器。

离线核心测试和模拟器只能验证协议编码及软件行为，不能替代实际门禁、手表音频和网络测试。

## 6. 常见问题

| 现象 | 检查方法 |
| --- | --- |
| 账户登录后无钥匙 | 刷新；用原服务确认账户及物业授权。不要自行填入门编号替代授权。 |
| 手表没有常用门 | 手机先设置常用门，再主动同步；确认手表网络可用。 |
| 手表“已配对”但一直 Connecting | 已配对不等于已连接。检查解锁状态、可互通的网络和 Device Hub 提示，再查看 `xcrun devicectl list devices`。 |
| 手机能安装，手表安装失败 | 检查 Watch Bundle ID/companion ID、手表开发者模式，以及手表 UDID 是否实际包含在描述文件中。 |
| 耳机连接时声波失败 | 确认输出切回设备内置扬声器并调高音量；按提示取消后重试。 |
| 无法扫描到门禁 | 检查蓝牙权限、距离、钥匙类型及授权。模拟器不代表真实 BLE 设备。 |
| 签名到期无法打开 | 同团队、同 Bundle ID 续签并覆盖安装，不先删除 App。 |

如果仍无法安装，保留系统错误原文及构建日志。历史设备发现故障记录是特定环境的调查材料，不是要求每个人重启、重置设备或修改系统保护的通用步骤。

## 7. 本地预览支持网站

```sh
python3 -m http.server 8766 --bind 127.0.0.1 --directory KeyPocket-Support/dist
```

在浏览器打开 `http://127.0.0.1:8766`。这里是静态支持和隐私说明页，不包含账户后台或开门服务。
