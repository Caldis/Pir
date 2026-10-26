# 维护索引

| 任务 | 入口 | 验证 |
| --- | --- | --- |
| 应用行为与界面 | `docs/architecture.md`, `Sources/`, `Tests/` | `scripts/check.sh`, 本机交互 |
| 原生偏好窗口 | `Sources/Pir/Preferences/PreferencesStyle.swift`, `Sources/Pir/Preferences/PreferencesWindowController.swift` | `PinManagementTests`, 本机页签与录制交互 |
| 热键录制与注册 | `THIRD_PARTY_NOTICES.md`, `Sources/Pir/`, `Sources/PirCore/` | 快捷键测试与跨应用触发 |
| 入门动画与快捷键试用 | `docs/platform-compatibility.md`, `Sources/Pir/WelcomeArtwork.swift`, `Sources/Pir/OnboardingDemo.swift` | `LogoBirthTests`, `OnboardingTests`, 本机试用与录制交互 |
| 图标与官网 | `assets/brand/`, `website/` | 静态检查与浏览器预览 |
| 构建与发布 | `.agents/docs/release.md`, `scripts/` | 签名、公证、Gatekeeper 与下载回读 |
| 应用更新与版本 | `docs/updates.md`, `Sources/Pir/Updates/`, `scripts/release/`, `scripts/version-metadata.py` | `UpdateTests`, `Tests/ReleaseTools`, 签名与安装回读 |
| 版本与范围 | `docs/plans/2026-10-25-v0.1.0.md` | 对照用户目标与验证记录 |
| 2026-10-26 会话交接 | `docs/handoff-2026-10-26.md` | 发布、真实更新与迁移收尾 |

历史文档提供上下文, 实际文件与本次执行结果提供当前事实
