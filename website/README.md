# Pir 官网

面向 Pir 用户的产品与下载页面, 静态产物部署在 GitHub Pages

## 本地开发

```sh
npm ci --ignore-scripts
npm run dev
```

## 构建

```sh
npm run build
npm run preview
```

输出目录为 `dist/`, 所有静态资源采用相对路径, 支持 GitHub Pages 的项目路径

下载入口默认指向 GitHub 最新 Release 页面, 浏览器成功读取公开 Release API 后, 下载入口指向同仓库最新 Release 的 DMG 资产

## 视觉与依赖

| 项目 | 实现 |
| --- | --- |
| 视觉主题 | 石墨色背景, 同时显示可交互的图片、文字与文件浮窗, 青色与紫色网格光场 |
| 字体 | 系统 Avenir Next, 中文 PingFang SC |
| 品牌图标 | `../assets/brand/`, 官网使用 256px 衍生图 |
| 动态艺术 | 固定版本 `shaders@4.0.5`, 原生 JavaScript `createShader` 与 MeshGradient、FilmGrain 组件 |
| 许可证 | Shaders 引擎与组件采用 MIT, 完整声明见 `public/third-party-licenses.txt` |

## 动态艺术生命周期

- 首屏演示进入视口后按需加载 WebGPU 引擎
- 系统减少动态效果、省流量与 WebGPU 能力状态决定静态降级
- 页面隐藏或演示离屏时停止背景动画
- 渲染尺寸使用移动端 640 与桌面 1100 的最长边像素预算, 预留 2x DPR
- GPU 初始化失败或设备丢失时显示 CSS 静态艺术
- 页面退出释放渲染器, 浏览器往返缓存恢复时继续同步播放状态
- `disableTelemetry: true` 关闭引擎遥测

## 设计决策

官网直接使用 Shaders 的 MIT 组件引擎. 官方 CLI 支持自然语言搜索、预览、编辑器项目同步, MCP 支持同类设计工作流; 官网使用独立配色与组件配置, 依赖仅限固定版本的 npm 包

实际运行官方 CLI `search 'iridescent glass floating spectral light' --limit 4 --json`, 成功返回 Floating Glass 7、2、3、4 预设. 预设与编辑器遵循独立服务条款, 官网当前采用 MIT 组件自行组合的视觉

Shaders 为 WebGPU 引擎, 浏览器能力决定动态效果是否启用. 浮窗、下载入口与页面内容采用 HTML 与 CSS. JavaScript 管理窗口的拖动、缩放、键盘与页面生命周期, 无 JavaScript 时仍能阅读与下载

动态引擎拆分为按需加载文件, 压缩后约 726 kB. 页面主交互压缩后约 8.5 kB, 首次 HTML 与 CSS 优先呈现

## 验证

```sh
npm test
node --check main.js
npm run build
```

浏览器验收覆盖 320、390、920 与 1280 px 布局、双语、三窗默认构图、浮窗跨区拖动、窗口缩放、视口回夹、方向键移动与缩放、演示入口有界复用、编辑内容与语言切换、下载链接和 WebGPU. ⌘⇧V 以 keycaps 显示, 创建示例图片而不读取剪贴板. 减少动态效果、组合键过滤与生命周期条件由纯逻辑回归覆盖, 实际系统设置与浏览器组合键仍需要本机补充验证.
