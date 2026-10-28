# Pir 维护速查

本文面向开发者与后续 agent. 阶段性发布状态见 handoff-2026-10-26.md, 版本号、流水线与安装状态以实时回读为准

## 接手顺序

1. 阅读 AGENTS.md 与 .agents/INDEX.md, 确认当前目录为 Pir 项目检出目录
2. 执行下列只读命令, 确认仓库身份、分支、已有改动和安装版本
3. 按维护索引读取相关源码和测试, 先复现问题再修改
4. 使用针对性验证确认修改, 发布前再执行完整检查与交互验收

```sh
pwd
git status --short --branch
git remote -v
git log -5 --oneline
/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' /Applications/Pir.app/Contents/Info.plist
/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' /Applications/Pir.app/Contents/Info.plist
```

多个会话共享当前 checkout. 提交前回读差异, 使用明确路径暂存并核对暂存区. 其他会话的已有修改保留在原状态

## 常用入口

所有命令在仓库根目录执行

| 操作 | 命令或入口 | 结果边界 |
| --- | --- | --- |
| 完整检查 | `scripts/check.sh` | Swift 测试、双语键、网站构建与路径、Python 发布测试、脚本语法 |
| Swift 编译 | `scripts/swift.sh build --jobs 2` | 当前架构开发编译 |
| 定向测试 | `scripts/swift.sh test --jobs 2 --filter PinPanelTests` | 对应 XCTest 类, 名称按 Tests 实际内容选择 |
| Universal 打包 | `scripts/build.sh` | 重建 dist/Pir.app, 生成临时签名开发产物 |
| 开发启动 | `scripts/dev.sh` | debug Universal 打包后打开 dist/Pir.app |
| 检查链接 SDK | `python3 scripts/check-build-sdk.py dist/Pir.app/Contents/MacOS/Pir` | 验证各架构 Mach-O SDK 记录 |
| 本地化检查 | `python3 scripts/check-localizations.py` | 原生与网站双语键集合 |
| 网站依赖与构建 | `npm ci --prefix website`, `npm run build --prefix website` | 可重复安装与本地网站产物 |
| 网站校验 | `python3 scripts/check-website.py` | 路径与发行下载链接 |
| 发布策略测试 | `python3 -B -m unittest discover -s Tests/ReleaseTools` | 版本、资产和 feed 工具行为 |
| 正式发行 | `scripts/release.sh` | 构建、签名、公证与 DMG 准备, 先读 .agents/docs/release.md |
| 更新资产准备 | `scripts/release/prepare-update.sh dist/Pir.app stable /path/to/notes.html` | 验证正式签名与票据, 生成签名 ZIP/feed, 写入本地 release/appcast.xml |

scripts/build.sh 会重建现有 dist/Pir.app. 正式签名应用和已验证的发行资产先保存独立副本, 再启动下一轮开发打包

脚本集中承担确定性操作, AGENTS.md 与维护文档承载约束和判断. 新增自动化前先核对 scripts/ 中的现有能力

## 定位源码与验证

| 问题 | 源码入口 | 测试或人工验收 |
| --- | --- | --- |
| 剪贴板类型与注册状态 | Sources/PirCore, HotKey/GlobalHotKey.swift | CoreTests, GlobalHotKeyTests |
| 录制 popover、keycaps 与清除 | HotKey/KeyRecorder.swift, KeyPopover.swift, Preferences/RecorderButton.swift | GlobalHotKeyTests, PinManagementTests, 欢迎页与设置分别操作 |
| 偏好窗口、页签尺寸与毛玻璃 | Preferences/PreferencesWindowController.swift, PreferencesStyle.swift | PinManagementTests, 高低页签连续切换 |
| 透明图片与悬停控件 | PinImageAppearance.swift, PinPanel.swift | PinPanelTests, 透明截图与白底图片实际悬停 |
| 文本自然尺寸、编辑与缩放 | PinTextSizing.swift, PinPanel.swift | PinPanelTests, PinSessionIntegrationTests, 窄窗长文本输入与撤销 |
| 会话、多屏与恢复 | PinManager.swift, Sources/PirCore | PinPersistenceTests, PinSessionIntegrationTests, 重启与显示器变化 |
| 文件图标、列表与拖放 | PinFilesView.swift | PinSessionIntegrationTests, Finder 实际拖出与双击 |
| 欢迎 Logo 与烟花 | WelcomeArtwork.swift, Onboarding.swift, OnboardingDemo.swift | LogoBirthTests, OnboardingTests, 连续快捷键与减少动态效果 |
| 关于与捐赠 | Preferences/AboutBrandArtwork.swift, AboutPreferencesController.swift, DonationController.swift | DonationLayoutTests, 深浅色和窗口 fittingSize |
| 更新 | Updates/UpdateManager.swift, UpdatePreferences.swift, scripts/release/ | UpdateTests, ReleaseTools, 较旧正式安装版本实际升级 |
| 双语 | Localization.swift, Resources/*.lproj, website/ | 双语键检查与两种语言界面回读 |

搜索优先使用 rg. 零命中结论先用固定字符串复核. 资源和包依赖变更同时核对 Package.swift、资源 bundle 与 THIRD_PARTY_NOTICES.md

## 运行时与 UI 验收

```sh
/usr/bin/log stream --level info --style compact --predicate 'subsystem == "me.caldis.pir"'
```

日志流使用后通过 SIGTERM 结束. 用户内容、登录态和签名材料保留在项目之外, 临时 fixture 记录独立标识并在验收后清理

原生界面与浏览器交互采用当前环境提供的 CUA 工具. 新会话重新绑定应用和标签页, 读取工具实际文档. 原会话的 JavaScript 变量只属于原 REPL

无边框浮窗可见而坐标操作返回 noWindowsAvailable 时, 使用浮窗暴露的 Raise 动作激活窗口, 再按最新 AX 控件索引操作. 本机文件视图切换已验证该路径, 截图与 AX 读取分别提供当前窗口状态

界面验证包含系统中文与英文、深浅外观、减少动态效果、短文本与长文本、透明与不透明图片. 截图呈现可见外观, 毛玻璃和切换动画还需直接观察. macOS CUA 的窗口枚举能力以工具实际返回为准

临时 AppleLanguages 覆盖、演示贴图和测试文件属于验收清理范围. 用户原有贴图与剪贴板内容保留

## 发布回读

```sh
gh repo view Caldis/Pir --json nameWithOwner,url,homepageUrl
gh release list --repo Caldis/Pir --limit 5
gh run list --repo Caldis/Pir --limit 5 --json databaseId,headSha,status,conclusion,name
codesign --verify --deep --strict /Applications/Pir.app
codesign -dvv /Applications/Pir.app
xcrun stapler validate /Applications/Pir.app
spctl --assess --type execute --verbose=2 /Applications/Pir.app
```

| 层级 | 有效证据 |
| --- | --- |
| 编译与测试 | 对应命令完整输出、退出码与测试范围 |
| 正式签名 | Developer ID Authority、团队身份与严格验签 |
| 公证 | notarytool Accepted、stapler 票据和 Gatekeeper accepted |
| 公开发行 | GitHub Release 回读、公开资产下载与 SHA256 对照 |
| 更新源 | 远端 feed 内容与本地仓库源一致, feed 与 ZIP 独立验签 |
| 更新安装 | 已安装旧版本实际发现、下载、安装与重启, 新版本与会话恢复回读 |
| 官网部署 | Pages 工作流和线上页面分别回读 |

Check workflow 产物为开发构建. Pages workflow 仅在网站相关路径变化或手动触发时部署. 发布记录同时写明代码 SHA、显示版本、构建号与资产名称

Sparkle 固定读取 update-feed prerelease 的 appcast.xml. 版本 Release 承载对应 ZIP, latest 查询用于稳定版下载. 公钥在 Info.plist, 原 Keychain account 为 me.caldis.pir, 私钥保留在 Keychain

Keychain 弹窗可能在路径迁移或工具重新访问密钥时出现. 应用控制工具拒绝操作 SecurityAgent 时, 保留进度并交给用户在系统窗口授权. 签名进程是否存活、资产是否生成均需独立回读

## 已验证的故障与处理

| 现象 | 已确认经验 |
| --- | --- |
| 本机与 CI 的原生样式有差异 | 检查链接 SDK 与当前 Xcode, scripts/swift.sh 同时传入 Swift SDK 和 Clang isysroot |
| 标准 SwiftPM 构建缺 Vortex 资源 | vendored 清单显式声明资源, 应用打包包含 Vortex_Vortex.bundle |
| 品牌替换后 npm ci 完整性失败 | package-lock integrity 为内容哈希, 保留原值, 品牌搜索命中与品牌语义分开判断 |
| 录制测试偶发取到旧 popover | 关闭动画期间旧窗口仍存在, 检查当前 recorder.popover |
| 原生按钮布局存在 1 pt 差异 | 保留系统绘制, 测试使用已确认的光学对齐容差 |
| 文本大内容缩放成本高 | 保持 TextKit 2 视口路径, 读取旧 TextKit 属性可能触发兼容回退 |
| 透明窗口截图出现异常外轮廓 | 检测四条外沿 alpha, 保留源图透明度, 悬停虚线表达可缩放区域 |
| 悬停阴影与透明贴图边界 | 控件使用径向渐变阴影, 与按钮同步显示且点击穿透; 透明贴图使用悬停虚线边界 |
| 页签缩小时内容漂移、背景露黑 | 内容锚定顶部, 整窗背景保持覆盖, 窗口尺寸动画与内容布局分别处理 |
| 同一热键录制缺反馈 | 已注册 Carbon 事件转交当前录制流程, 显示成功反馈 |
| 发行 target 返回 422 | gh --target 使用完整 40 位提交 SHA |
| GitHub 资产标签正确但文件名错误 | file#label 只改展示标签, 上传前使用正确实际文件名 |
| 测试末尾显示 Swift Testing 0 tests | 同时检查 XCTest 实际执行列表与进程退出码 |

## 设计决策

Pir 的基础热键功能使用系统组合键注册与应用窗口内录制. 当前权限模型与 Mos 的全局事件处理需求分别维护

文件浮窗采用公开 URL 与拖放 API, 右键仅提供移除引用. 系统公开接口缺少完整 Finder 右键菜单, 当前产品范围保留轻量文件暂存交互

项目级文档承载本项目可复用经验, 本轮采用现有脚本与维护索引. 跨项目复用需求明确后再提取独立 skill, 技能评测依用户当轮授权执行

## 2026-10-28 本地开发与签名排查

构建主机 开发目录为 `项目检出目录`. Xcode 26.6 / Swift 6.3.3 / SDK 26.5 已通过 Universal 构建, `scripts/dev.sh` 启动后更新页显示 0.1.9 / 20261028.1. `scripts/check.sh` 通过 128 项 Swift 测试、6 项 Python 发布工具测试、本地化、网站和脚本检查. 缩放光标测试使用隔离的合成事件队列, 保留原有精确尺寸与光标断言, 避免 AppKit 在真实队列中转换合成坐标.

Developer ID 证书、配对私钥与 P12 一直位于 构建主机 的 `${PIR_SIGNING_DIR}/`, 说明位于 `${PIR_SIGNING_GUIDE}`. 单独看到证书而 `security find-identity` 未列出可用身份, 应继续检查配对私钥与钥匙串加载状态. 本轮已将配对材料导入 login Keychain; 发行实际使用临时钥匙串加载同一套本地材料, 完成后恢复搜索列表并清理临时钥匙串. OpenSSL 3 打包给 macOS 导入的临时 P12 使用 `-legacy`, 随机口令不写入仓库或日志. Developer ID 签名、应用与 DMG 公证均已验证.

Pir 的 Sparkle 更新密钥与 Developer ID 分开管理. 原有账号 `${PIR_SPARKLE_ACCOUNT}` 位于 更新签名主机 `${PIR_SPARKLE_HOST}` 的 login Keychain, 公钥与本仓库 Info.plist 匹配. 当前 构建主机 未配置这把更新密钥, 不应据此认定原密钥不存在. 普通 SSH 调用可能被系统拒绝访问钥匙串, 本轮在 更新签名主机 的 Aqua 用户会话运行原有 Sparkle 工具, 用独立临时目录处理本机已公证应用, 私钥与原项目工作区保留原处. 后续继续使用该机器签名, 或在明确迁移密钥后核对两机公钥; 不得重新生成或替换发布公钥.


## 本地维护配置

机器相关的维护设置统一使用仓库外 `~/.config/pir/maintenance/local.env`，初始化与缺失输入处理见维护技能的 `references/local-environment.md`。新 worktree 复用该配置，普通构建/测试不依赖发布配置。Project 状态同步和通知失败只保留待恢复状态；实际 issue 工作与验收按自身依赖继续，已验收完成的文档/网站/工具任务不创建空应用版本。
