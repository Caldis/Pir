# 发布流程

本文面向开发者与发布 agent

## 本地配置

签名支持 macOS Keychain 中的 Developer ID Application 身份或 Xcode 云管理 Developer ID 导出, 公证使用 Keychain profile `notarytool`

| 环境变量 | 用途 |
| --- | --- |
| `PUV_SIGN_IDENTITY` | 可选 Developer ID Application 证书名称或 SHA1; 留空时使用 Xcode 云签名导出 |
| `PUV_TEAM_ID` | Xcode 云签名团队 ID, 本项目默认 N7Z52F27XK |
| `PUV_DEVELOPMENT_IDENTITY` | 可选开发签名身份; 云导出前用于归档签名 |
| `PUV_NOTARY_PROFILE` | 公证 Keychain profile, 默认 notarytool |
| `PUV_VERSION` | 应用版本, 默认 Resources/Info.plist 当前值 |
| `PUV_BUILD` | 唯一构建编号 |

凭据仅保存在 Keychain 或项目之外的 `.env` 文件, 日志仅记录证书名称与公证提交 ID

## 步骤

1. 执行 `scripts/check.sh`, 并完成图片、文本、热键与偏好设置交互验收
2. 执行 `scripts/release.sh`, 按需通过 `PUV_SIGN_IDENTITY` 指定本地分发证书
3. 脚本构建 Universal app、签名、提交公证、装订票据并验证 Gatekeeper
4. 脚本生成 `dist/Puv-<version>-universal.dmg`, 验证磁盘镜像与 SHA256
5. GitHub Release 使用上述最终镜像与校验文件, 官网下载指向 Releases
6. 下载已发布镜像并比对 SHA256, 挂载后验证应用签名与装订票据

## 证书恢复

`security find-identity -v -p codesigning` 仅列出可用身份. 缺少 Developer ID 身份时, 检查 Xcode Accounts 的账号与团队状态, 使用 Xcode 的 Developer ID 导出能力恢复分发证书. Apple Development 身份只适用于开发构建

公证 `Accepted` 之后才执行 `stapler staple`; 构建通过、已上传与公证通过分别记录

云签名模式通过 `scripts/cloud-sign.sh` 导出签名后的应用, 分发私钥保留在 Apple 的签名服务. 磁盘镜像包含 Developer ID 签名应用并单独接受公证与票据装订; 使用本地分发身份时镜像另加签名

## 0.1.0 验证记录

构建编号为 20261025.3, 本机检查执行 44 项 XCTest, 网站构建、静态资源路径与脚本语法检查通过

| 项目 | 回读结果 |
| --- | --- |
| Universal | x86_64 + arm64, macOS 13+ |
| 应用签名 | Developer ID Application: BIAO CHEN, N7Z52F27XK, Hardened Runtime |
| 应用公证 | Accepted, 314bc1f6-a42b-4ad4-9c01-1ad7355b7b94 |
| DMG 公证 | Accepted, 8548b61d-7d51-4196-8270-b722c1f5e16a |
| 票据与执行评估 | app 与 DMG stapler validate 通过, Gatekeeper accepted / Notarized Developer ID |
| DMG 完整性 | hdiutil verify 通过, 下载校验使用 Release 的 SHA256SUMS |
| 入门动画 | 原生窗口捕获描边帧与完成帧, 运行日志在约 4.3 秒后记录 settled |
| 会话 | NSPanel 重启回读、隐藏状态、显式删除及恢复失败保留回归通过 |

物理显示器拔插与 macOS 13 实机尚待验证, 当前覆盖屏幕拓扑模型与本机窗口恢复. 未授权辅助功能时, 权限引导继续使用系统设置窗口外框定位; 详细边界见 docs/platform-compatibility.md
