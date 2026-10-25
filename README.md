# Puv

一个快捷键, 图片与文字留在屏幕上

Puv 是 macOS 菜单栏应用, 支持剪贴板图片与文本贴屏. 每张贴图以独立无边框窗口置顶显示, 支持移动、缩放与关闭

[官网](https://caldis.github.io/Puv/) · [下载](https://github.com/Caldis/Puv/releases/latest)

## 使用

1. 下载磁盘镜像, 拖动 Puv 到 Applications
2. 启动 Puv, 复制一张图片或一段文字
3. 按 `⇧⌘V` 创建贴图
4. 拖动贴图调整位置, 从边缘调整大小, 悬停后点击复原或关闭

文本保留换行与缩进, 背景和文字颜色跟随 macOS 明暗主题

图片采用 cover 填充, Retina 截图保留逻辑显示尺寸. 应用重启后恢复贴图内容、尺寸与位置, 多显示器位置按屏幕归属保存

贴图会话保存在本机 `~/.config/puv/`, 用户关闭单张贴图时清理对应数据

## 偏好设置

点击菜单栏图标, 选择偏好设置. 贴图页面列出全部浮窗, 支持再次贴上、隐藏、显示、删除与清空全部, 隐藏状态随应用重启恢复

首次启动显示 Logo 入门动画. 点击快捷键区域可录制组合键, 按下快捷键即可试贴 Logo, 并观看屏幕烟花. 快捷键触发与窗口内录制均免辅助功能权限

| 设置 | 功能 |
| --- | --- |
| 开机启动 | 登录 macOS 时启动 Puv |
| 隐藏图标 | 隐藏菜单栏图标; 再次启动 Puv 可打开偏好设置 |
| 热键 | 录制创建贴图的全局快捷键 |

## 系统要求

macOS 13 或更新版本, 支持 Apple Silicon 与 Intel Mac

## 开发

维护入口为 [AGENTS.md](AGENTS.md), 架构见 [docs/architecture.md](docs/architecture.md), 构建与发布见 [.agents/docs/release.md](.agents/docs/release.md)

## 许可

Puv Source License 1.0. 允许使用、修改与共享源码, 第三方在应用商店分发同类应用需要作者书面授权. 作者保留官方发行与 Mac App Store 上架权利

此许可属于源码可用许可, 来源与第三方声明见 [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)
