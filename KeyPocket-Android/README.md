# 钥匙口袋 · Android 1.0

与 iPhone 版对应的独立原生 Android 客户端。Android 8.0（API 26）及以上；面向 Android 16（API 36）。Java / 系统 View、BluetoothGatt、AudioTrack；没有第三方运行依赖，不加载原 App 的广告、统计或 native SDK。

## 安装和使用

跨平台步骤见 [使用、构建与安装指南](../docs/HOWTO.md)。本仓库不包含预编译 APK；按下方构建步骤生成 `build/KeyPocket-Android-1.0.apk`，传到安卓手机，打开 APK 并按系统提示允许此来源安装。应用包名 `local.keypocket.android`，可与官方钥匙宝并存。构建脚本默认使用本机开发证书签名，后续覆盖升级需沿用同一证书。

1. 用已有钥匙宝手机号、短信验证码登录，随后同步钥匙。认证只返回登录令牌时，也会继续调用独立的钥匙同步接口。
2. 打开「钥匙配置」，选择门，设为常用，可设置本机别名、顺序、蓝牙/声波方式和声波频段。
3. 到门边，在「常用门」点击开门。蓝牙首次使用会请求附近设备权限；Android 8–11 需要定位权限及系统定位开关才能扫描，本 App 不读取 GPS 位置。
4. 声波使用媒体音量，需至少 40%；它会暂时打断其他音频。仅在确认实际输出为内置扬声器后生成并发送限时声波。如系统不能切换扬声器，会要求断开耳机。通话时不播放声波。
5. 「已发送」表示请求传输完成，实际门的状态需要现场确认。

## 常用钥匙快捷入口

- 将钥匙设为常用后，长按桌面 App 图标，显示最多 4 把常用钥匙（受桌面支持及数量限制）。
- 钥匙设置 →「添加到桌面」可固定单把钥匙。系统会让你确认添加。
- 下拉快捷设置面板 → 编辑 → 添加「常用门」磁贴，点按即可打开常用门页。锁屏时需解锁。
- 外部快捷入口先选中钥匙，确认后才发送开门请求。旧账户、已取消常用或撤销的钥匙不能借旧快捷方式发送请求。
- Android 各品牌实体操作按钮/多功能键的系统接口不同；本版提供桌面快捷方式与标准快捷设置磁贴，厂商按键绑定需要按具体机型配置。

## 账户、授权和可靠性

登录令牌用 Android Keystore 的 AES-GCM 密钥加密保存，禁用系统备份。门的授权字段由服务器提供，本机设置只控制别名、常用、顺序和传输方式。每次开门重新同步授权并使用服务器时间；支持需要额外服务器验证的蓝牙钥匙类型 6/7。会话失效会清除本机登录。

蓝牙采用单个串行 GATT 会话，逐项发现、读取挑战、验证及带响应写入。连接阶段最多重试一次；一旦开始写入实际开门数据，绝不自动重发。收到全部写入确认后，设备立即断开仍视为「已发送」。离开 App 或取消操作会停止扫描、连接或音频。

声波复用 iPhone 版已验证的编码：TEA、Modbus CRC、CCITT CRC、RS(15,13)、重复符号映射、44.1 kHz 单声道 PCM。标准 / 低频 / 高频基频分别为 12200 / 9000 / 17000 Hz，符号间隔 150 Hz。不会请求麦克风权限。

服务器沿用原应用的 HTTP 加密封装，明文网络例外只允许 `app.keyboot.com`。未更改服务端认证、账户权限或门禁设备固件。次数访客等未验证的钥匙类型保持不支持。

## 构建

当前 Mac 已安装 Android SDK Platform 36、Build Tools 36.0.0、Platform Tools，以及用于测试的 Android 15 ARM64 模拟器。没有安装 Android Studio。

无需 Gradle 下载的已验证构建路径（JDK 17+，另需 Python 3、zip）：

```sh
./scripts/build-apk.sh
# 输出 build/KeyPocket-Android-1.0.apk
```

默认 SDK 路径：`~/Library/Android/sdk`；其他位置设置 `ANDROID_SDK_ROOT`。脚本使用 `aapt2 → javac → d8 → zipalign → apksigner`。开发签名保存在 `~/.android/debug.keystore`，不会打包到源码 ZIP 中。构建时缺少该证书会创建标准本机开发证书。

也可在 Android Studio 中导入本目录，或使用自行安装的 Gradle 8.11.1 执行 `gradle :app:assembleDebug`。项目声明 AGP 8.10.1、Compile SDK 36、Build Tools 36.0.0。Gradle 路径尚未在此环境执行；本次交付 APK 来自上述已验证 SDK 脚本。

## 验证

```sh
./scripts/test-core.sh
# 63 项离线断言：纯 JVM，org.json 仅为测试依赖，不打入 App
./scripts/test-device.sh
# 仅允许 adb -e 指定的模拟器；请使用无账户的测试模拟器
```

已完成：APK v2/v3 签名验证、63 项核心断言、Android 15 模拟器 13 项运行时检查（Keystore、快捷方式、账户隔离、退出和权限声明）、登录 / 常用门 / 配置 / 钥匙设置页面截图检查。测试使用合成账户和合成钥匙，未发起真实登录、短信或开门请求。

待实测：真实账户登录、真实门禁 BLE、声波扬声器路由与连接蓝牙耳机的表现；尚未连接安卓真机。截图见 [docs/screenshots](docs/screenshots/)，其中已登录页面均为明确标记的测试数据。

协议源依据为相邻 iPhone 项目的 `Core/Sources/KeyPocketCore` 与既有 APK 分析记录；蓝牙、声波结果分别与既有 Java/native 黄金样例核对。

参考：
- [Android 蓝牙权限](https://developer.android.com/develop/connectivity/bluetooth/bt-permissions)
- [音频路由 API](https://developer.android.com/reference/android/media/AudioRouting)
- [桌面快捷方式 API](https://developer.android.com/reference/android/content/pm/ShortcutManager)
- [AGP 8.10 / SDK 36 兼容说明](https://developer.android.com/build/releases/agp-8-10-0-release-notes)
