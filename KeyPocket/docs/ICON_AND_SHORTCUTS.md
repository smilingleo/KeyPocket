# 1.2：图标与系统快捷指令

图标采用深森林绿背景、暖白钥匙与门的组合。使用 imagegen skill 的 built-in image_gen 模式生成，再机械缩放为 iPhone AppIcon 所需尺寸。项目中的主图：`KeyPocket/Assets.xcassets/AppIcon.appiconset/Icon-1024@1x.png`。

生成提示词：
Use case: logo-brand. Asset type: production iPhone app icon, square full-bleed 1024x1024 artwork. Design a beautiful premium minimalist icon for a personal door-key app called KeyPocket. A single bold, original ivory-white geometric key subtly integrated with an open doorway through negative space; visually clear at 48px, elegant balanced silhouette, compact and centered, large generous visual weight. Deep dark forest-teal background with a very subtle luminous emerald gradient, warm ivory main glyph, restrained soft dimensional enamel finish and a tiny gentle highlight, no busy effects. Contemporary refined calm design, exceptionally crisp clean edges, large simple shapes, strong contrast. Fill the entire square background to every edge; iOS applies its own rounded mask, so do not draw rounded outer corners, outer frame, border, padding outside the background, phone mockup, text, letters, logos from other brands, watermark, multiple variants or a presentation sheet. Deliver ONE standalone app-icon image.

## 配置菜单

1. 打开钥匙口袋，刷新钥匙，在配置页将目标门设为常用。
2. 打开系统「快捷指令」，新建快捷指令，添加钥匙口袋的「打开常用门」动作，点「常用门」选择目标钥匙，命名保存。
3. 如已有多功能菜单快捷指令：在其「从菜单中选取」中增加一个菜单项，在该分支加入「运行快捷指令」，选择刚才保存的开门快捷指令。
4. 如使用机身操作按钮：设置 → 操作按钮 → 快捷指令，选择菜单快捷指令。长按按钮运行菜单。
5. 如使用辅助触控浮动按钮：设置 → 辅助功能 → 触控 → 辅助触控，将自定义操作（长按）绑定到该菜单快捷指令，或在自定顶层菜单中选择可用的快捷指令。

系统菜单需要用户在手机上选择绑定。App 无权修改操作按钮或现有快捷指令菜单。执行动作会打开 App；锁屏时需先完成身份验证。动作沿用目标门的蓝牙/声波配置，每次重新获取授权，已撤销、非当前账户或已取消常用的钥匙不会发送开门命令。不代表门已实际打开。

实体目录只保存显示名称和随机账户命名空间下的钥匙标识，不保存协议密钥或登录 token。退出或失效登录会清空目录。

验证：现有 18 项 Core 测试通过；iPhone 签名构建成功，App Intents 元数据包含可选择钥匙参数、前台执行和 requiresAuthentication。Xcode 27.2 的可选 Siri SSU 归档阶段报错，但动作元数据已成功生成；Siri 自然语言唤起尚未验证。未自动执行真实开门动作；菜单与门口实测需在手机进行。

参考：
- https://support.apple.com/en-cn/guide/iphone/iphe89d61d66/ios
- https://support.apple.com/zh-cn/guide/iphone/iph96b21954/27/ios/27
- https://developer.apple.com/documentation/appintents/appintent/authenticationpolicy
