# 贴图渲染与回归验证

本文面向开发者与后续 agent

## 文本

文本贴图使用系统 NSTextView 的 TextKit 2 引擎, 通过 NSScrollView 提供竖向滚动. 文本保留原始换行、空格与缩进, 长行随窗口宽度折行, 最小窗口尺寸为 120 × 80 points

文本视图使用 `NSTextView(usingTextLayoutManager: true)`, 文本容器宽度跟随视图, 水平最小尺寸为零. 生产代码仅请求视口布局, 文档内容与字体属性在创建时设置一次

## 图像

图像使用 Core Animation 的 `resizeAspectFill`, 保持比例并居中裁切覆盖整个贴图窗口

剪贴板读取优先采用 TIFF, 从像素尺寸与 DPI 恢复原始 points 尺寸. Retina TIFF 的 800 × 600 pixels 对应 400 × 300 points. 下采样保留原始逻辑尺寸, NSBitmapImageRep 独立保存有上限的位图分辨率

## 设计决策

[Apple 的 TextKit 更新说明](https://developer.apple.com/videos/play/wwdc2022/10090/)确认 TextKit 2 采用视口布局, 适用于大文档, macOS Ventura 的 TextEdit 同样使用该引擎. 显式访问 NSTextView 的 `layoutManager` 会触发 TextKit 1 兼容模式, Puv 使用 `textLayoutManager` 路径

[Apple 的 TextKit 2 介绍](https://developer.apple.com/videos/play/wwdc2021/10061/)建议布局工作集中在可见视口, 全文布局请求可能带来显著开销

实际参考的成熟实现为 [STTextView](https://github.com/krzyzanowskim/STTextView). 其[视口布局实现](https://github.com/krzyzanowskim/STTextView/blob/c7d519318b06ebb7a99a641e4aa8831105d3b7d4/Sources/STTextViewAppKit/STTextView%2BNSTextViewportLayoutControllerDelegate.swift)围绕可见区域预取、复用片段视图并回收离屏片段. Puv 的只读纯文本范围适合系统 NSTextView, 视口管理交给 AppKit, 系统基线保持 macOS 13

## 实测

验证环境为 arm64、macOS 27.2、Swift 6.4、Debug 构建

| 场景 | 结果 |
| --- | --- |
| 120 × 80 points 文本窗口 | 全文字符串保留, 最后一行可通过竖向滚动到达, TextKit 2 保持启用 |
| 横向图像放入纵向窗口 | 实际位图渲染验证上下边缘 alpha 大于 0.95, 图像填满窗口 |
| Retina TIFF | 800 × 600 pixels 读取为 400 × 300 points |
| 790000 UTF-8 bytes、20000 行文本 | 实际窗口在 120 与 680 points 宽度之间调整 40 次, 布局与显示请求累计耗时约 0.123 秒 |

性能测量覆盖重复调整尺寸后的布局与显示请求, 初次创建与 GPU 最终合成耗时属于测量范围之外. macOS 13 与 14 的性能表现仍需对应系统实测

回归入口为 `Tests/PuvUITests/PinPanelTests.swift` 与 `Tests/PuvCoreTests/CoreTests.swift`
