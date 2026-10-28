# 应用更新

本文面向开发者与发布 agent

## 更新界面

更新页采用 Mos 的 120 pt 紧凑布局, 提供立即检查、当前版本与构建号、启动时检查和包含测试版

UpdateManager 使用 Sparkle 2.10.0 的标准下载、安装、重启与错误界面. 启动时检查默认为关闭, 开启后在下次启动两秒后检查. 手动检查始终可用. 包含测试版控制 beta channel, 稳定 channel 始终参与版本选择

偏好保存于应用 UserDefaults. 应用菜单仍然只保留偏好设置与退出

## 版本与资产

| 项目 | 稳定版 | 测试版 |
| --- | --- | --- |
| 显示版本 | `X.Y.Z` | `X.Y.Z` |
| 构建编号 | `YYYYMMDD.N` | `YYYYMMDD.N` |
| Git tag | `X.Y.Z` | `X.Y.Z-beta-YYYYMMDD.N` |
| 更新 ZIP | `Pir.Versions.X.Y.Z-YYYYMMDD.N.zip` | `Pir.Versions.X.Y.Z-beta-YYYYMMDD.N.zip` |
| Sparkle channel | 默认 channel | `beta` |

N 从 1 开始. 本地构建从现有 dist/Pir.app 读取同日序号并递增, 日期使用 Asia/Shanghai; CI 与正式发行可通过 PIR_BUILD 显式指定编号. 每次分发使用递增的构建编号, 同一显示版本的重新打包也增加编号. Sparkle 按构建编号比较更新顺序. `scripts/version-metadata.py` 校验版本与日期并输出资产名称, `scripts/release/update-feed.py` 另行检查 appcast 中的历史构建编号

## GitHub Releases

更新 feed 地址为 `https://github.com/Caldis/Pir/releases/download/update-feed/appcast.xml`

独立的 update-feed release 采用 prerelease 标记, 资产 appcast.xml 同时收录稳定版和测试版. 每个版本的 ZIP 位于各自版本 release. 下载入口校验 GitHub 主机与 Caldis/Pir 的 releases/download 路径. Sparkle 处理 GitHub 到资产 CDN 的 HTTPS 重定向

`release/appcast.xml` 是签名 feed 的仓库源文件. Pir 0.1.2 开始提供独立的 Sparkle 更新 ZIP 与 appcast

## 更新签名

Pir 使用独立的 Ed25519 密钥, Keychain account 为 `${PIR_SPARKLE_ACCOUNT}`. 公钥保存在 Resources/Info.plist 的 SUPublicEDKey. 原有私钥保存在 更新签名主机 `${PIR_SPARKLE_HOST}` 的 login Keychain; 构建主机 不持有该密钥

Info.plist 启用 SURequireSignedFeed 和 SUVerifyUpdateBeforeExtraction. Sparkle 验证 feed、ZIP 签名与应用签名, 安装要求用户确认

`scripts/release/configure-update-key.sh` 创建或读取 Pir 的 Keychain 密钥并更新公钥配置. `scripts/sparkle-tool.sh` 从 SwiftPM artifact 定位官方工具, PIR_SPARKLE_TOOLS 可指定官方发行包的 bin 目录

Pir 的 Keychain 密钥与公钥配置已完成. 本机使用该 Keychain account 的 ZIP fixture 与 feed 签名及独立验签均已通过, 一次性隔离密钥的同项检查也已通过, 临时密钥在验证后清理. 发行工具再次访问 Keychain 时, macOS 仍可能要求授权. 普通 SSH 会话可能返回 Keychain access blocked; 使用该机器登录用户的 Aqua 会话运行原有工具, 并核对公钥是否与 Info.plist 一致. 临时工作目录用于签名资产, 私钥保留在原机器, 原项目工作区保持不变

## 本地准备

1. 执行常规验证与 Universal 构建
2. 完成 Developer ID 签名、公证与 app 票据装订
3. 执行 `scripts/release/prepare-update.sh dist/Pir.app stable /path/to/release-notes.html`, 测试版使用 beta
4. 回读 dist/updates 中的 ZIP、appcast.xml 与 SHA256SUMS, 并检查 release/appcast.xml 的历史条目

准备脚本校验应用标识、版本递增、公钥匹配与 Developer ID 签名, 验证公证票据, 生成 ZIP、签名 ZIP、生成并签名 appcast, 随后独立验证两个签名. 此脚本只处理本地文件

## 发布与验收

版本 release 发布 ZIP 后, 更新 update-feed release 的 appcast.xml 资产. appcast 的仓库提交与远端 feed 资产使用相同内容

发布操作沿用任务的用户授权范围. 发布后下载两个资产并验证 SHA256 与 EdDSA 签名, 再使用较旧的已安装版本验收发现更新、下载、安装、重启与贴图恢复. 本地构建和签名验证分别提供准备证据, 公开更新安装使用发布后的端到端证据

## 设计决策

Sparkle 提供经过维护的 macOS 更新与安装流程. 独立 update-feed prerelease 同时承载两个 channel, GitHub 的 latest release 查询只包含稳定版, 应用直接读取固定 feed 地址

签名 feed 认证版本元数据和发布说明, ZIP 的独立 EdDSA 签名认证下载内容. Pir 独立 Keychain account 使应用更新密钥与 Mos 的密钥分别管理

协议与 API 依据 [Sparkle 官方配置文档](https://sparkle-project.org/documentation/) 和 [纯代码接入文档](https://sparkle-project.org/documentation/programmatic-setup/)
