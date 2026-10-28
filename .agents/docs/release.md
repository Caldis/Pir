# 发布流程

本文面向开发者与发布 agent

## 本地配置

签名使用 macOS Keychain 中带有对应私钥的本地 Developer ID Application 身份, 公证使用 Keychain profile `notarytool`

| 环境变量 | 用途 |
| --- | --- |
| `PIR_SIGN_IDENTITY` | 必填, 本地 Developer ID Application 签名身份的证书名称或 SHA1 |
| `PIR_NOTARY_PROFILE` | 公证 Keychain profile, 默认 notarytool |
| `PIR_VERSION` | 应用版本, 默认 Resources/Info.plist 当前值 |
| `PIR_BUILD` | 唯一构建编号 |

凭据仅保存在 Keychain 或项目之外的 `.env` 文件, 日志仅记录证书名称与公证提交 ID

## 步骤

1. 执行 `scripts/check.sh`, 并完成图片、文本、热键与偏好设置交互验收
2. 执行 `PIR_SIGN_IDENTITY="Developer ID Application: BIAO CHEN (N7Z52F27XK)" scripts/release.sh`, 指定本地分发身份
3. 脚本构建 Universal app、签名、提交公证、装订票据并验证 Gatekeeper
4. 脚本生成 `dist/Pir-<version>-universal.dmg`, 验证磁盘镜像与 SHA256
5. GitHub Release 使用上述最终镜像与校验文件, 官网下载指向 Releases
6. 下载已发布镜像并比对 SHA256, 挂载后验证应用签名与装订票据

## 证书恢复

`security find-identity -v -p codesigning` 仅列出可用身份. 证书可见但身份不可用时, 检查同一 Keychain 中是否存在配对私钥、证书有效期与信任链; 按需导入包含私钥的证书备份, 再用 `codesign` 实际验证. Apple Development 身份只适用于开发构建

本机签名材料位于 `~/Docs/ci-signing/keys/dev-id-app.p12`、`dev-id-app.key` 与 `dev-id-app.pem`, 配置记录位于 `~/Docs/ci-signing/github-macos-codesign.md`. 这些文件保留在仓库之外. 证书身份为 `Developer ID Application: BIAO CHEN (N7Z52F27XK)`, SHA1 为 `A23AFFD4C701B02874A7855F92E832D5D45707E2`. 身份未出现在钥匙串列表时, 先检查该本地备份与配对私钥, 再验证签名能力.

公证 `Accepted` 之后才执行 `stapler staple`; 构建通过、已上传与公证通过分别记录


## 原生外观与链接 SDK

编译与测试使用 scripts/swift.sh, Universal 打包继续使用 scripts/build.sh. 包装脚本通过 xcrun 获取 SDK, 同时传递 --sdk 与 Clang 链接驱动的 -isysroot. scripts/check-build-sdk.py 检查各架构的 Mach-O SDK 记录

最低系统版本 minos 为 13.0, SDK 为当前构建工具链版本. 本机检查记录为 SDK 27.0. 页签与按钮使用 AppKit 原生外观, SDK 记录参与系统兼容行为选择

## Sparkle 更新资产

更新界面、GitHub Release feed、独立更新签名与版本策略见 docs/updates.md. scripts/build.sh 嵌入 Sparkle.framework 并签名组件, release.sh 在根应用签名前使用相同发行身份重签组件

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

## 0.1.4 发行验收

2026-10-26 完成正式发行, 显示版本 0.1.4, 构建编号 20261026.6. 功能提交为 0b08460b1f6f608e3db3ed791411f5a6134e50a3, 签名 feed 提交为 7c4a4867d2b1c52199908a9d0577ffa519a6a63d

| 范围 | 结果 |
| --- | --- |
| Issue 审计 | 全量读取 #1 至 #12 及评论, 作者均为 Caldis; 依赖与文件边界记录于 docs/plans/2026-10-26-issues-1-12.md |
| 子代理 | 浮窗几何与欢迎页并行实施, 同模块按依赖串行; 主 agent 实施文件交互并统一验证与发行 |
| 本地检查 | scripts/check.sh 通过, 104 项 Swift 测试、5 项 Python 发布测试、双语资源与网站检查通过 |
| Universal 构建 | arm64 与 x86_64, 最低 macOS 13, 两个架构的链接 SDK 为 27 |
| 应用签名 | Developer ID Application: BIAO CHEN, Team N7Z52F27XK, 严格验签通过 |
| 应用公证 | Apple Accepted, 提交 9b6c7b88-f926-4b14-b14c-dd72775bb27c, stapler 与 Gatekeeper 通过 |
| DMG 公证 | Apple Accepted, 提交 3ddf19bb-67ad-4439-9f64-7b42adfa98b4, 票据与镜像校验通过 |
| 公开发行 | [Pir 0.1.4](https://github.com/Caldis/Pir/releases/tag/0.1.4), DMG 与更新 ZIP 的公开下载 SHA256 一致 |
| 更新签名 | 公开 feed 与仓库文件逐字节一致, feed 与 ZIP 经应用公钥独立 Ed25519 验签通过 |
| 公开 DMG | 下载后只读挂载, 镜像内应用的严格验签、票据与 Gatekeeper 通过 |
| 实际更新 | 已安装 0.1.3 / 20261026.5 通过 Sparkle 发现、下载、安装并自动重启至 0.1.4 / 20261026.6 |
| 安装回读 | 已安装应用的 118 个常规文件与公开更新 ZIP 一致, 签名、票据与 Gatekeeper 通过; 再次检查显示当前为最新版本 |
| 会话恢复 | 四项隔离会话的 8 个内容与元数据文件在更新前后一致, 覆盖文本、文件、透明图片、欢迎 Logo 及隐藏状态 |
| UI 验收 | 文件相交框选与选中态、右键菜单、隔离文件改名与废纸篓、原生简介、默认 Shift + Command + V、欢迎大按钮与连续试用完成本机回读 |
| 透明输入 | WindowServer 边缘命中测试通过; 同步条件下 alpha 0 对照失败, 1/255 输入环通过 |
| CI | 功能提交 [40261692910](https://github.com/Caldis/Pir/actions/runs/40261692910) 与 feed 提交 [40261844493](https://github.com/Caldis/Pir/actions/runs/40261844493) 均成功 |
| 官网与 issue | 官网品牌和下载入口回读通过, latest API 指向 0.1.4, #1 至 #12 独立回读均为 closed / completed |

Limited Review: 真实多显示器断开、透明浮窗拖动和完整悬停动效的人工观察仍有限. 桌面自动化在透明浮窗拖动时返回 noWindowsAvailable, 文件原生移动操作未取得确定的手势完成证据. 移动通知、手势结束复位、临时迁移、最小尺寸、边缘命中、按钮布局与动画终态具备回归测试; 烟花随机区域、三倍规格、资源上限及减少动态效果具备定向测试. 这些测试分别提供对应机制的证据

发行证据与隔离会话归档位于 ~/.config/pir/migration/release-verification/0.1.4/, 截图位于 /Users/caldis/.codex/visualizations/2026/10/26/01a17595-51e9-79e3-b92f-0fe6e1f3718f/. 日志为 /tmp/pir-0.1.4-final-check.log、/tmp/pir-0.1.4-build.log、/tmp/pir-finalize-0.1.4.log、/tmp/pir-prepare-0.1.4.log、/tmp/pir-public-0.1.4-verify.log 与 /tmp/pir-public-0.1.4-dmg.log

发行资产为 Pir-0.1.4-universal.dmg、Pir.Versions.0.1.4-20261026.6.zip 与 SHA256SUMS. 隔离验收会话已归档, 用户偏好与 Keychain 密钥继续保留

## 0.1.5 发行验收

2026-10-26 完成正式发行, 显示版本 0.1.5, 构建编号 20261026.7. 功能提交为 1b3715e17f7ee51d4fc25fe6732c6e34506213a9, 签名 feed 提交为 317b3011f8d114190cdc73b5198336474e9a5169

| 范围 | 结果 |
| --- | --- |
| Issue 与实施 | Caldis 提交的 #13 至 #15 完成; 浮窗控件串行实施, 持久化与文档并行, 独立只读审查完成 |
| 本地检查 | scripts/check.sh 通过, 112 项 Swift 测试、5 项 Python 发布测试、113 组原生双语键与网站检查通过 |
| 构建 | arm64 与 x86_64 Universal, 最低 macOS 13, 链接 SDK 为 27 |
| 应用公证 | Developer ID Application: BIAO CHEN, Team N7Z52F27XK; Apple Accepted, 提交 41059424-1da3-48a9-a7a1-abe788ee66e9, 票据与 Gatekeeper 通过 |
| DMG 公证 | Apple Accepted, 提交 7d7484b8-91d3-46f4-bd83-e53520b22e85, 票据与镜像校验通过 |
| 公开发行 | [Pir 0.1.5](https://github.com/Caldis/Pir/releases/tag/0.1.5), 公开 DMG 与 ZIP 的 SHA256 一致, 公开 feed 与仓库逐字节一致 |
| 独立验签 | 应用公钥验证公开 feed 与 ZIP 的 Ed25519 签名通过; 公开 ZIP 与只读挂载 DMG 内的应用均通过签名、票据与 Gatekeeper 验证 |
| 实际更新 | 已安装 0.1.4 / 20261026.6 通过 Sparkle 发现、下载、安装并自动重启至 0.1.5 / 20261026.7, 再次检查显示最新版 |
| 安装回读 | 已安装应用的 118 个常规文件与公开更新 ZIP 一致 |
| 会话恢复 | 两项隔离会话保留原有元数据和内容资产; 新元数据增加 imageScaling=cover, 旧格式恢复兼容性通过 |
| 图片外观 | 实际应用显示 cover 中部裁剪与 fit 完整三色图片, 两次恢复的窗口均为 240 × 240 pt; 缩放模式恢复和再次贴上另有集成回归 |
| 控件回归 | 关闭优先顺序、复制成功/失败/重复触发/定时恢复、原始图像复制、模式切换与原始 frame、fit 留白边缘 WindowServer 命中均通过 |
| CI | 功能提交 [40265675396](https://github.com/Caldis/Pir/actions/runs/40265675396) 与 feed 提交 [40265890971](https://github.com/Caldis/Pir/actions/runs/40265890971) 均成功 |
| Issue 回读 | #13 至 #15 关闭为 completed; 独立 gh issue view/list 回读为 CLOSED, open 列表为空 |

Limited Review: 桌面自动化未能稳定触发悬停工具条, 完整过渡动画的实际观感仍有限. 实际应用证据覆盖 cover 与 fit 的恢复静帧及真实升级, 控件交互与反馈时序使用定向回归证据

证据、公开下载、日志和隔离会话归档位于 ~/.config/pir/migration/release-verification/0.1.5/. 截图位于 /Users/caldis/.codex/visualizations/2026/10/26/01a17595-51e9-79e3-b92f-0fe6e1f3718f/. 定时任务状态位于 ~/.config/pir/issue-monitor/state.json

## 0.1.6 发行验收

2026-10-26 完成正式发行, 显示版本 0.1.6, 构建编号 20261026.8. 功能提交为 31738460d2b485ddc8b1660e81fb08bafc182e8f, 签名 feed 提交为 65076781658e0466de8b86228ae93c068fb70685

| 范围 | 结果 |
| --- | --- |
| Issue 与实施 | Caldis 提交的 #16、#17 完成; 共享浮窗源码串行实施, 文档并行, 新增需求分别完成聚焦只读审查 |
| 本地检查 | scripts/check.sh 通过, 119 项 Swift 测试、5 项 Python 发布工具测试、双语、网站与脚本检查通过 |
| 构建 | arm64 与 x86_64 Universal, 最低 macOS 13, 链接 SDK 为 27 |
| 图片工具条 | 全部图片采用均匀半透明圆角背景, 透明图片保留外置子面板, 文本与文件沿用径向背景 |
| 虚线与光标 | 白底与深底对比、动画中间帧四边可见性、内部透明、fit 留白状态、八方向光标事件与手势方向锁定通过定向回归 |
| 图片尺寸过渡 | cover / fit 采用 bounds 与 position 插值, 起点、中间帧、终点及 presentation 反向接续通过, 原始 bitmap 与窗口 frame 回归通过 |
| 应用公证 | Developer ID Application: BIAO CHEN, Team N7Z52F27XK; Apple Accepted, 提交 89b4e246-2278-4dcd-a933-7f8cc83f118e, 票据与 Gatekeeper 通过 |
| DMG 公证 | Apple Accepted, 提交 a33cdf33-54ca-4e6d-b9be-5c06de5059de, 票据与镜像校验通过 |
| 公开发行 | [Pir 0.1.6](https://github.com/Caldis/Pir/releases/tag/0.1.6), 公开 DMG 与 ZIP 的 SHA256 一致, 公开 feed 与仓库逐字节一致 |
| 独立验签 | 应用公钥验证公开 feed 与 ZIP 的 Ed25519 签名通过; 公开 ZIP 与只读挂载 DMG 内的应用通过签名、票据与 Gatekeeper |
| 实际更新 | 已安装 0.1.5 / 20261026.7 通过 Sparkle 发现、下载、安装并自动重启至 0.1.6 / 20261026.8, 再次检查显示最新版 |
| 安装与会话 | 已安装应用的 118 个常规文件与公开 ZIP 一致; 透明图片、fit 图片和隐藏文本的 6 个内容与元数据文件升级前后一致, 管理页状态回读通过 |
| CI | 功能提交 [40270960297](https://github.com/Caldis/Pir/actions/runs/40270960297) 与 feed 提交 [40270976068](https://github.com/Caldis/Pir/actions/runs/40270976068) 均成功 |
| Issue 回读 | #16 与 #17 关闭为 completed, 独立 gh issue view 回读为 CLOSED |

Limited Review: 桌面自动化对非激活浮窗 hover 和拖动的支持有限, 本轮鼠标操作未取得确定的缩放完成证据. 实际应用证据覆盖图片静态渲染、fit 恢复、管理页与真实升级; 完整悬停观感和应用失活时的鼠标投递仍属有限人工覆盖. 光标事件路由、手势锁定、虚线和图片过渡采用定向回归证据

证据、公开下载、日志和隔离会话归档位于 ~/.config/pir/migration/release-verification/0.1.6/. 隔离会话已归档, 用户偏好与 Keychain 密钥继续保留. 新增图片图层在 CI 的 1x 窗口取整下存在 cover 外扩, 测试采用等比、居中与完整覆盖断言, 对应修正后的功能 CI 通过


## 0.1.7 发行验收

2026-10-26 完成正式发行, 显示版本 0.1.7, 构建编号 20261026.9. 功能合并提交为 b09501fbd462f59f24e8ea7a9cc75fdcb34be590, 签名 feed 提交为 d61402501961109ffa57df7a63b8c6c0fb571144

| 范围 | 结果 |
| --- | --- |
| Issue 与实施 | Caldis 提交的 #18、#19、#20 完成, PR #21 合入 main; 共享图片源码串行实施, 文件模块独立回归, 聚焦审查完成 |
| 检查与构建 | 127 项 Swift 测试、5 项 Python 发布工具测试、本地化、网站与脚本检查通过; arm64/x86_64 Universal, 最低 macOS 13, SDK 27 |
| 图片外观 | 白线外侧暗色对比、四边与圆角、动画起中终点像素、内部透明、120/131/132/360 pt 工具条布局与命中、按钮白色绘制与按压反馈通过回归 |
| 文件布局 | legacy 与 overlay 滚动条、自然三列、窄窗口降列、移除与视图切换恢复通过 6 项回归; 实际应用确认 304 pt 自然宽度三列、列表切换与竖向滚动条 |
| 应用公证 | Developer ID Application: BIAO CHEN, Team N7Z52F27XK; Apple Accepted, 提交 bbded082-79c6-4af4-924b-7e4ff4363575, 票据与 Gatekeeper 通过 |
| DMG 公证 | Apple Accepted, 提交 c0a172e4-9e36-4374-af33-f944db491f24, 票据与镜像校验通过 |
| 公开发行 | [Pir 0.1.7](https://github.com/Caldis/Pir/releases/tag/0.1.7), 公开 DMG 与 ZIP 的 SHA256 一致, 公开 feed 与仓库逐字节一致 |
| 独立验签 | 公开 feed 与 ZIP 经应用公钥独立 Ed25519 验签通过; 公开 ZIP 与只读挂载 DMG 内的应用通过签名、票据与 Gatekeeper |
| 实际更新 | 已安装 0.1.6 / 20261026.8 通过 Sparkle 下载、安装并自动重启到 0.1.7 / 20261026.9, 再次检查显示最新版 |
| 安装与会话 | 已安装应用的 118 个常规文件与公开 ZIP 一致; 两项图片、隐藏文本与隐藏文件列表的 8 个内容和元数据文件在升级前后一致, 管理页状态回读通过 |
| CI | 合并提交 [40294273762](https://github.com/Caldis/Pir/actions/runs/40294273762) 与 feed 提交 [40294450633](https://github.com/Caldis/Pir/actions/runs/40294450633) 均成功 |
| Issue 回读 | #18、#19、#20 均为 closed / completed; 独立 gh 查询的 open 列表为空 |

Limited Review: 桌面自动化对非激活浮窗 hover 的投递支持有限, 完整工具条与虚线过渡观感仍属有限人工覆盖. 实际应用证据覆盖透明图片渲染、文件网格和列表、会话恢复与真实升级; 像素、几何、命中和时序具备定向回归证据


证据、公开下载、日志与本轮隔离会话位于 ~/.config/pir/migration/release-verification/0.1.7/. 预览会话与升级会话分别归档, 用户偏好与既有 Keychain 密钥保留, 已安装正式版恢复常规运行

## 0.1.8 发行验收

2026-10-28 完成正式发行, 显示版本 0.1.8, 构建编号 20261027.1. 功能合并提交为 f256c887c414d5348f867160a828b1960436d233, 签名 feed 提交为 52ddafe7c98fddce67deb456ba24a684f11ffaab

| 范围 | 结果 |
| --- | --- |
| Issue 与实施 | Caldis 提交的 #22 完成, PR #23 合入 main; Bundle 资源名加载在 1x 环境选择 18 px 图标, 在 2x 环境选择 36 px 图标 |
| 检查与构建 | 128 项 Swift 测试、5 项 Python 发布工具测试、本地化、网站与脚本检查通过; arm64/x86_64 Universal, 最低 macOS 13, SDK 27 |
| 分发签名 | 复用 Mac mini 的既有 Developer ID Application: BIAO CHEN, Team N7Z52F27XK; 临时钥匙串导入后签名, 严格验签通过 |
| 应用公证 | asc 的 d2r profile 提交, Apple Accepted, 提交 c45cf6db-b6f0-4458-9651-44ff63f27773; 票据与 Gatekeeper 通过 |
| DMG 公证 | Developer ID 签名, Apple Accepted, 提交 9b1d0eb4-03a0-4cd9-9d7b-66de1888b406; 票据、签名与镜像校验通过 |
| 公开发行 | [Pir 0.1.8](https://github.com/Caldis/Pir/releases/tag/0.1.8), 公开 DMG 与更新 ZIP 的 SHA256 一致, 公开 feed 与仓库逐字节一致 |
| 独立验签 | 公开 feed 与 ZIP 经应用公钥独立 Ed25519 验签通过; 公开 ZIP 与只读挂载 DMG 内的应用通过签名、票据与 Gatekeeper |
| 实际更新 | 已安装 0.1.7 / 20261026.9 通过 Sparkle 下载、安装并自动重启至 0.1.8 / 20261027.1, 再次检查显示最新版 |
| 安装与会话 | 已安装应用的 118 个常规文件与公开 ZIP 一致; 三项文件与文本会话保留内容、尺寸、位置和隐藏状态, 元数据补入默认 imageScaling=cover |
| CI | PR [40492891077](https://github.com/Caldis/Pir/actions/runs/40492891077)、功能合并 [40493506246](https://github.com/Caldis/Pir/actions/runs/40493506246) 与 feed [40623356439](https://github.com/Caldis/Pir/actions/runs/40623356439) 均成功 |
| Issue 回读 | #22 关闭为 completed |

Limited Review: 桌面工具截图覆盖应用窗口, 系统菜单栏的整体视觉对比仍属有限人工覆盖. 回归测试与打包后探针验证实际 1x/2x representation 选择, 两份 PNG 保持原始像素

签名证书、私钥和 P12 的实时位置为 SSH 主机 macmini 的 /Users/caldis/Docs/ci-signing/keys/. 本轮临时钥匙串签名使用原有文件, 结束后恢复钥匙串搜索列表并清理临时材料.

发行证据、独立公开下载、日志与测试会话归档位于 ~/.config/pir/migration/release-verification/0.1.8/. 已安装正式版恢复常规运行, 用户偏好与原有凭据保留
