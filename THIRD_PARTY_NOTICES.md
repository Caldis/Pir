# 第三方与来源声明

## Mos

Puv 的键盘录制交互与按键显示实现提取并适配自 [Mos](https://github.com/Caldis/Mos), 作者 Caldis / BIAO CHEN

- 来源提交: `752730c2a156fbff45c8745eb4fadf188d8b9fd6`
- 来源文件: `Mos/Keys/KeyRecorder.swift`, `Mos/Keys/KeyPreview.swift`, `Mos/Keys/KeyPopover.swift`, `Mos/Keys/KeyCode.swift`
- 适配范围: 键盘组合键录制、修饰键显示、取消、超时与录制结果反馈; Puv 使用独立全局热键注册服务
- 来源许可证: Attribution-NonCommercial 4.0 International, https://creativecommons.org/licenses/by-nc/4.0/
- 相关实现版权归 Caldis / BIAO CHEN, 此处 Puv 副本经版权所有者授权适用仓库 `LICENSE` 中的 Puv Source License 1.0; Mos 仓库原有许可保持原状

## Shaders

官网使用 shader-effects-inc/shaders, 版本与完整 MIT 许可声明见 `website/package-lock.json` 及 `website/` 中的依赖许可文件

项目地址: https://github.com/shader-effects-inc/shaders

## PermissionFlow

入门窗口的系统设置授权引导使用 [PermissionFlow](https://github.com/jaywcjlove/PermissionFlow), 版本 2.11.4, 作者 jaywcjlove

上游采用 MIT 许可证, 完整声明随应用资源与仓库依赖许可文件提供

源码包保存在 `Vendor/PermissionFlow`, 上游提交与本地定位适配记录见 `Vendor/PermissionFlow/UPSTREAM.md`
