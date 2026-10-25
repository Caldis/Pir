# 维护索引

| 任务 | 入口 | 验证 |
| --- | --- | --- |
| 应用行为与界面 | `docs/architecture.md`, `Sources/`, `Tests/` | `scripts/check.sh`, 本机交互 |
| 热键录制与注册 | `THIRD_PARTY_NOTICES.md`, `Sources/Puv/`, `Sources/PuvCore/` | 快捷键测试与跨应用触发 |
| 入门动画与权限兼容 | `docs/platform-compatibility.md`, `Sources/Puv/WelcomeArtwork.swift`, `Vendor/PermissionFlow/UPSTREAM.md` | `swift test --filter LogoBirthTests`, 入门与系统设置交互 |
| 图标与官网 | `assets/brand/`, `website/` | 静态检查与浏览器预览 |
| 构建与发布 | `.agents/docs/release.md`, `scripts/` | 签名、公证、Gatekeeper 与下载回读 |
| 版本与范围 | `docs/plans/2026-10-25-v0.1.0.md` | 对照用户目标与验证记录 |

历史文档提供上下文, 实际文件与本次执行结果提供当前事实
