# App Store Connect 注册记录

2026-11-04 已通过用户当前登录的浏览器完成：

- App 名称：钥匙口袋
- 平台：iOS
- 主要语言：简体中文
- Apple ID：6830434379
- Bundle ID：net.smilingleo.KeyPocket
- SKU：KEYPOCKET-IOS
- 付费开发者 Team ID：TLAMM3823Y
- 当前状态：Prepare for Submission（准备提交）
- 管理页面：https://appstoreconnect.apple.com/apps/6830434379/distribution

Apple Developer 的 Identifiers 列表已显示 KeyPocket / net.smilingleo.KeyPocket；App Store Connect 的 App 列表也已显示“钥匙口袋”。本次未上传构建、未提交审核、未公开发行，也未接受新的法律协议。

## 发行配置

新增 `Configuration/AppStore.xcconfig`，通过构建时显式指定来使用已注册的 App Store 身份：

```sh
env DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  xcodebuild -project KeyPocket.xcodeproj -scheme KeyPocket \
  -configuration Release -xcconfig Configuration/AppStore.xcconfig \
  -destination 'generic/platform=iOS' \
  -archivePath build/AppStore/KeyPocket.xcarchive archive
```

已通过 `xcodebuild -showBuildSettings` 验证有效 Bundle ID 和 Team ID。尚未运行此归档命令；Xcode 仍需能访问该付费开发者账户的发行签名权限。现有默认测试配置仍使用原个人团队和 `local.keypocket.iphone`，此前手机测试包不会自动变成 App Store 构建。

## 后续提交所需资料

- 使用发行身份生成并上传构建，确认 App Store Connect 版本号与构建版本匹配。
- 补充商店截图、描述、支持网址、隐私政策网址和隐私申报。
- 准备审核可用的登录方式，以及门禁硬件相关功能的审核说明。
- 当前网页提示付费应用协议（Paid Applications Schedule）有更新；若提交被协议拦截，需要账户持有人查看并明确接受。开发者账户页已显示主许可协议此前接受，因此没有代替用户再次接受。

以上记录仅表示已注册 App 并建立商店草稿，不表示审核通过或已上架。
