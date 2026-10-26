# 发布流程

本文面向开发者与发布 agent

## 本地配置

签名支持 macOS Keychain 中的 Developer ID Application 身份或 Xcode 云管理 Developer ID 导出, 公证使用 Keychain profile `notarytool`

| 环境变量 | 用途 |
| --- | --- |
| `PIR_SIGN_IDENTITY` | 可选 Developer ID Application 证书名称或 SHA1; 留空时使用 Xcode 云签名导出 |
| `PIR_TEAM_ID` | Xcode 云签名团队 ID, 本项目默认 N7Z52F27XK |
| `PIR_DEVELOPMENT_IDENTITY` | 可选开发签名身份; 云导出前用于归档签名 |
| `PIR_NOTARY_PROFILE` | 公证 Keychain profile, 默认 notarytool |
| `PIR_VERSION` | 应用版本, 默认 Resources/Info.plist 当前值 |
| `PIR_BUILD` | 唯一构建编号 |

凭据仅保存在 Keychain 或项目之外的 `.env` 文件, 日志仅记录证书名称与公证提交 ID

## 步骤

1. 执行 `scripts/check.sh`, 并完成图片、文本、热键与偏好设置交互验收
2. 执行 `scripts/release.sh`, 按需通过 `PIR_SIGN_IDENTITY` 指定本地分发证书
3. 脚本构建 Universal app、签名、提交公证、装订票据并验证 Gatekeeper
4. 脚本生成 `dist/Pir-<version>-universal.dmg`, 验证磁盘镜像与 SHA256
5. GitHub Release 使用上述最终镜像与校验文件, 官网下载指向 Releases
6. 下载已发布镜像并比对 SHA256, 挂载后验证应用签名与装订票据

## 证书恢复

`security find-identity -v -p codesigning` 仅列出可用身份. 缺少 Developer ID 身份时, 检查 Xcode Accounts 的账号与团队状态, 使用 Xcode 的 Developer ID 导出能力恢复分发证书. Apple Development 身份只适用于开发构建

公证 `Accepted` 之后才执行 `stapler staple`; 构建通过、已上传与公证通过分别记录

云签名模式通过 `scripts/cloud-sign.sh` 导出签名后的应用, 分发私钥保留在 Apple 的签名服务. 磁盘镜像包含 Developer ID 签名应用并单独接受公证与票据装订; 使用本地分发身份时镜像另加签名

## 原生外观与链接 SDK

编译与测试使用 scripts/swift.sh, Universal 打包继续使用 scripts/build.sh. 包装脚本通过 xcrun 获取 SDK, 同时传递 --sdk 与 Clang 链接驱动的 -isysroot. scripts/check-build-sdk.py 检查各架构的 Mach-O SDK 记录

最低系统版本 minos 为 13.0, SDK 为当前构建工具链版本. 本机检查记录为 SDK 27.0. 页签与按钮使用 AppKit 原生外观, SDK 记录参与系统兼容行为选择

## Sparkle 更新资产

更新界面、GitHub Release feed、独立更新签名与版本策略见 docs/updates.md. scripts/build.sh 嵌入 Sparkle.framework 并签名组件, cloud-sign.sh 与 release.sh 在根应用签名前使用相同发行身份重签组件

Pir 的发行源为 Caldis/Pir. 发布后独立回读应用、镜像、更新 ZIP 与签名 feed, 更新安装结果记录于本文件

## 0.1.3 发行验收

2026-10-26 完成正式发行, 显示版本 0.1.3, 构建编号 20261026.5. 功能提交为 217a9175bda7ab17df86a47941a5b9f07cc7a664, 签名 feed 提交为 7e10bb7c2e3abddd6093bce10b2a69aaed6c4406

| 范围 | 结果 |
| --- | --- |
| 本地检查 | scripts/check.sh 通过, 78 项 Swift 测试、5 项 Python 发布测试、双语键与网站检查通过 |
| Universal 构建 | arm64 与 x86_64, 最低 macOS 13, 两个架构的链接 SDK 为 27 |
| 应用签名 | Developer ID Application: BIAO CHEN, Team N7Z52F27XK, 严格验签通过 |
| 应用公证 | Apple Accepted, 提交 5e755cbe-da11-4c01-8b0e-8fd2bc5e8a7f, stapler 与 Gatekeeper 通过 |
| DMG 公证 | Apple Accepted, 提交 2089a6d7-4fc8-4639-aed0-3a9f62e29490, stapler 与镜像校验通过 |
| 公开发行 | [Pir 0.1.3](https://github.com/Caldis/Pir/releases/tag/0.1.3), DMG 与更新 ZIP 的公开下载 SHA256 一致 |
| 更新签名 | 公开 feed 与仓库文件逐字节一致, feed 与 ZIP 经应用公钥独立 Ed25519 验签通过 |
| 实际更新 | 已安装 0.1.2 / 20261026.4 通过 Sparkle 发现、下载、安装并自动重启至 0.1.3 / 20261026.5 |
| 安装回读 | 已安装应用的 120 个文件与公开更新 ZIP 一致, 签名、票据与 Gatekeeper 通过, 再次检查显示当前为最新版本 |
| 会话恢复 | 独立文本、单文件和六文件测试会话的 6 个内容与元数据文件在升级前后一致, 包含尺寸与隐藏状态 |
| UI 验收 | 贴屏名称、原双方框页签、新空态插图、16 pt 帮助按钮及弹层、文件图标与列表切换、单文件高度、文本与文件材质完成本机回读 |
| CI | 功能提交 [40250205404](https://github.com/Caldis/Pir/actions/runs/40250205404) 与 feed 提交 [40250360378](https://github.com/Caldis/Pir/actions/runs/40250360378) 均成功 |
| 官网 | https://caldis.github.io/Pir/ 返回成功, 品牌与下载入口回读通过, latest API 指向 0.1.3 |

公开资产名称为 Pir-0.1.3-universal.dmg 与 Pir.Versions.0.1.3-20261026.5.zip. SHA256SUMS 记录两个固定发行资产, 动态 feed 使用独立签名认证

本机证据位于 ~/.config/pir/migration/release-verification/, 日志位于 /tmp/pir-release-final-check.log、/tmp/pir-release-final-build.log、/tmp/pir-finalize-0.1.3-final.log 与 /tmp/pir-prepare-0.1.3-final.log. 截图位于 /Users/caldis/.codex/visualizations/2026/10/26/01a17595-51e9-79e3-b92f-0fe6e1f3718f/

验收测试会话已归档. 旧应用位于 ~/.config/pir/migration/archived-applications/Puv.app, 原用户数据、迁移备份和 Keychain 密钥保留. 登录项数据库读取超时, 数据库记录保持原状

Limited Review: 文件网格、尺寸、引用持久化、移除保留源文件、拖放 URL writer、透明边界与按钮状态有定向测试; 本次人工交互覆盖视图切换和窗口外观, Finder 拖出与双击打开沿用既有有限验收范围
