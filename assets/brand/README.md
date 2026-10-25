# Puv 品牌资产

面向应用维护者与后续 agent

| 文件 | 用途 |
| --- | --- |
| `app-icon.png` | 1024px 应用图标原图, 透明外边角 |
| `AppIcon.icns` | macOS 应用图标, 含 16px 至 1024px 尺寸 |
| `AppIcon.iconset/` | `iconutil` 输入尺寸集合 |
| `MenuBarTemplate.svg` | 菜单栏小写 p 与折角 v 标记的矢量母版 |
| `MenuBarTemplate.png` | 18px 单色透明菜单栏图标 |
| `MenuBarTemplate@2x.png` | 36px Retina 菜单栏图标 |

菜单栏图标作为 template 使用, 显示尺寸为 18 × 18 pt, AppKit 按系统外观着色

修改菜单栏矢量母版后, 在项目根执行 `swift scripts/render-menu-icon.swift` 更新 1x 与 2x 位图

## 图标生成

应用图标采用内置 imagegen 生成, 菜单栏标记采用小写 p 与折角 v 组合

生成提示词:

> Use case: logo-brand. Asset type: final macOS application icon for Puv, a focused clipboard-to-floating-panel app. Create one original exceptionally refined macOS icon with the craft and legibility of a premium productivity app. Scene/backdrop: a very dark graphite rounded macOS squircle with subtle material depth, surrounded by genuinely transparent outer corners. Subject: centered single sculptural symbol made of two hovering folded rectangular glass planes, one upper-right smaller plane and one lower-left larger plane overlapping, their negative space subtly forming a lowercase p silhouette. Each plane is broad, clean, gently chamfered, geometrically precise; the overall silhouette must remain distinct at 32 pixels. Style: exquisite shader art, iridescent refractive glass and brushed luminous metal, carefully controlled spectral edge reflections in icy cyan, soft violet and warm coral, dark calm interior surfaces. Lighting: one cinematic soft top left key light, subtle contact shadow within the squircle, high contrast crisp silhouette. Composition: straight-on icon view, generously sized central symbol covering 65 percent of the tile; dark tile occupies 86 percent of the square image with equal transparent margin. No lettering, no text, no pin, no clipboard, no paperclip, no screenshots, no other icons, no grid, no presentation board. The image itself is a single finished square 1024px icon, truly transparent outside rounded tile
