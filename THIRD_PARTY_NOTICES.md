# 第三方与来源声明

## Mos

Puv 的键盘录制交互、按键显示与偏好页签图标提取并适配自 [Mos](https://github.com/Caldis/Mos), 作者 Caldis / BIAO CHEN

- 来源提交: `752730c2a156fbff45c8745eb4fadf188d8b9fd6`
- 来源文件: `Mos/Keys/KeyRecorder.swift`, `Mos/Keys/KeyPreview.swift`, `Mos/Keys/KeyPopover.swift`, `Mos/Keys/KeyCode.swift`
- 图标文件: `Mos/Assets.xcassets/Preferences/SF.gearshape.imageset/SF.gearshape.svg`, `Mos/Assets.xcassets/Preferences/SF.person.crop.circle.dashed.imageset/SF.person.crop.circle.dashed.svg`
- 捐赠资源: `Mos/Assets.xcassets/Donate/MEOW.imageset`, `AlipayQR.imageset`, `WechatpayQR.imageset`; 付款入口沿用 Mos 的作者账号
- 适配范围: 键盘组合键录制、修饰键显示、取消、超时与录制结果反馈; Puv 使用独立全局热键注册服务
- 来源许可证: Attribution-NonCommercial 4.0 International, https://creativecommons.org/licenses/by-nc/4.0/
- 相关实现版权归 Caldis / BIAO CHEN, 此处 Puv 副本经版权所有者授权适用仓库 `LICENSE` 中的 Puv Source License 1.0; Mos 仓库原有许可保持原状

## Shaders

官网使用 shader-effects-inc/shaders, 版本与完整 MIT 许可声明见 `website/package-lock.json` 及 `website/` 中的依赖许可文件

项目地址: https://github.com/shader-effects-inc/shaders

## Vortex

欢迎页的屏幕烟花使用 [Vortex](https://github.com/twostraws/Vortex), 版本 1.0.4, 作者 Paul Hudson

上游采用 MIT 许可证, 完整声明见 `licenses/Vortex.txt`, 随应用资源一起分发. 固定源码与资源清单适配见 `Vendor/Vortex/UPSTREAM.md`

## Sparkle

应用更新使用 [Sparkle](https://github.com/sparkle-project/Sparkle), 版本 2.10.0

完整许可证与第三方声明见 `licenses/Sparkle.txt`, 随应用资源一起分发
