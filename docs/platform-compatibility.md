# 平台兼容性

读者: Pir 维护者与后续 agent

## 当前支持

发布目标为 macOS 13+, 同时包含 Intel 与 Apple Silicon 架构

| 功能 | 当前系统边界 | macOS 12 适配工作 |
| --- | --- | --- |
| 登录启动 | SMAppService, macOS 13+ | 嵌入独立 Login Item helper, 使用 SMLoginItemSetEnabled, 补齐签名与登录启动回归 |
| 试用烟花 | Vortex 1.0.4, macOS 12+ | 在 Monterey 验证渲染与窗口生命周期 |
| 文本贴图 | TextKit 2, macOS 12+ | 在 Monterey 验证长文本视口布局、窄窗口换行与缩放 |
| Logo 入门动画 | MetalKit | Metal 设备不可用时显示静态应用图标 |

## 入门动画

LogoBirth.metal.txt 在运行时编译, 使用应用当前图标纹理生成轮廓绘制、材质显现与光效

动画局限于独立 Metal 视图, 文字与按钮保持固定布局; 4.2 秒后暂停渲染, 窗口关闭时释放显示回调

窗口遮挡或最小化暂停动画, 再次可见后继续; 减少动态效果开启时直接显示最终静帧

Metal 编译与分阶段渲染使用 LogoBirthTests 验证; 设置 PIR_ARTWORK_SNAPSHOT_DIR 后测试可导出 PNG 帧供视觉验收

## 快捷键试用

Carbon 注册负责全局快捷键触发, NSEvent local monitor 负责应用窗口内录制. Pir 的当前流程免辅助功能权限

Vortex 烟花使用透明、点击穿透的 NSPanel, 显示于欢迎窗口所在屏幕, 结束后释放渲染资源. 减少动态效果开启时保留 Logo 贴图并跳过烟花

## 设计决策

当前发布目标保留 macOS 13; 降低目标至 macOS 12 涉及登录 helper 与真实旧系统验收, 单独修改 deployment target 仅能改变声明

macOS 11 缺少当前 TextKit 2 视口渲染基础, 需要独立的文本布局实现与大文本性能验证

## 参考

- [Apple SMAppService](https://developer.apple.com/documentation/servicemanagement/smappservice)
- [Apple NSTextView](https://developer.apple.com/documentation/appkit/nstextview)
- [Vortex 1.0.4](https://github.com/twostraws/Vortex/tree/1.0.4)
