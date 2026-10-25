# 平台兼容性

读者: Puv 维护者与后续 agent

## 当前支持

发布目标为 macOS 13+, 同时包含 Intel 与 Apple Silicon 架构

| 功能 | 当前系统边界 | macOS 12 适配工作 |
| --- | --- | --- |
| 登录启动 | SMAppService, macOS 13+ | 嵌入独立 Login Item helper, 使用 SMLoginItemSetEnabled, 补齐签名与登录启动回归 |
| 权限引导 | PermissionFlow 2.11.4 标注 macOS 13+, 使用 System Settings 导航 | 适配 Monterey System Preferences 的入口、窗口结构与浮窗定位 |
| 文本贴图 | TextKit 2, macOS 12+ | 在 Monterey 验证长文本视口布局、窄窗口换行与缩放 |
| Logo 入门动画 | MetalKit | Metal 设备不可用时显示静态应用图标 |

## 入门动画

LogoBirth.metal.txt 在运行时编译, 使用应用当前图标纹理生成轮廓绘制、材质显现与光效

动画局限于独立 Metal 视图, 文字与按钮保持固定布局; 4.2 秒后暂停渲染, 窗口关闭时释放显示回调

窗口遮挡或最小化暂停动画, 再次可见后继续; 减少动态效果开启时直接显示最终静帧

Metal 编译与分阶段渲染使用 LogoBirthTests 验证; 设置 PUV_ARTWORK_SNAPSHOT_DIR 后测试可导出 PNG 帧供视觉验收

## 权限浮窗定位

PermissionFlow 的浮窗、拖拽卡片与过渡动画保留上游实现, 本地源码包记录在 Vendor/PermissionFlow/UPSTREAM.md

系统允许读取辅助功能层级时, 跟踪器识别列表末尾相邻的添加与移除按钮, 浮窗紧贴该行下缘; 列表延伸到窗口底部时使用窗口底边

辅助功能尚未授权时, Window Server 仅提供窗口外框, 列表内部控件坐标不可读取; 该状态保留紧贴系统设置窗口底边的定位

## 设计决策

当前发布目标保留 macOS 13; 降低目标至 macOS 12 涉及登录 helper、第三方权限库兼容分支与真实旧系统验收, 单独修改 deployment target 仅能改变声明

macOS 11 缺少当前 TextKit 2 视口渲染基础, 需要独立的文本布局实现与大文本性能验证

权限引导采用公开窗口几何与可用的辅助功能信息; 屏幕录制权限、Automation 权限与私有 API 会扩大首次授权范围, 本版本保留现有授权边界

## 参考

- [Apple SMAppService](https://developer.apple.com/documentation/servicemanagement/smappservice)
- [Apple NSTextView](https://developer.apple.com/documentation/appkit/nstextview)
- [PermissionFlow 2.11.4](https://github.com/jaywcjlove/PermissionFlow/tree/65434c9ae04dba97cf52c1dffbe3e4e62b547c82)
