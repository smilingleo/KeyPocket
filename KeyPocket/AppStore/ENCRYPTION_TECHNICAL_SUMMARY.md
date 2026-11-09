# 加密技术说明（供准备 Apple 合规材料）

应用：钥匙口袋 / KeyPocket；Bundle ID `net.smilingleo.KeyPocket`；版本 1.3（5）。

## 代码中实际存在的加密

- 网络封装使用 Apple CommonCrypto 提供的 AES-256-CBC 和 PKCS#7 padding，兼容原钥匙宝服务的请求/响应。封装内容包括认证、授权同步及权限检查数据。
- 蓝牙门禁协议由本 App 的 Swift 代码实现 TEA（128-bit key，64-bit block，32 rounds），用于设备挑战响应和开门协议处理。
- 声波授权也使用 Swift 实现的 TEA，以及校验/纠错编码。CRC、Reed–Solomon 编码和音频调制本身不被本说明当作加密算法。
- 本机账户存储使用 Apple Keychain。
- 不提供通用加密文件、消息或 VPN 服务；加密用于兼容账户服务及门禁设备协议。此用途描述不自动构成出口管制豁免判断。

代码位置：`Core/Sources/KeyPocketCore/Protocol.swift`、`SoundProtocol.swift`、`KeyPocket/Keychain.swift`。

## Apple 页面观察

构建已上传并关联。App Store Connect 显示 `Missing Compliance`。在加密问卷中查看并选择“Encryption algorithms that are proprietary or not accepted as standard by international standard bodies (IEEE, IETF, ITU, etc.)”后，Apple 页面要求在 App Encryption Documentation 中上传材料，待批准后提供 Xcode 配置值。

此选择基于应用自行实现的 TEA 兼容协议；没有保存虚假的“不使用这些算法”答案，也没有设置 `ITSAppUsesNonExemptEncryption = false` 来绕过问卷。

## 仍需账户持有人处理的事项

确认应用适用的正式加密分类/豁免及 Apple 所需材料。如果已有厂商或原服务针对此用途的分类资料，可用于核实；否则需要根据 Apple 的出口合规流程准备材料。本技术说明是实现清单，不是政府分类文件、法律意见或获批的合规证明。应用是否可适用豁免不能仅凭本代码清单确认。

参考：
- https://developer.apple.com/help/app-store-connect/manage-app-information/overview-of-export-compliance
- https://developer.apple.com/documentation/security/complying-with-encryption-export-regulations
