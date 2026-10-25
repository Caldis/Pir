# Puv 官网

面向 Puv 用户的产品与下载页面, 静态产物部署在 GitHub Pages

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
| 视觉主题 | 石墨色背景, 桌面与独立图片、文字浮窗, 青色与紫色光谱背景 |
| 字体 | 系统 Avenir Next, 中文 PingFang SC |
| 品牌图标 | `../assets/brand/`, 官网使用 256px 衍生图 |
| 动态艺术 | 固定版本 `shaders@4.0.5`, 原生 JavaScript `createShader` 与 Aurora 组件 |
| 许可证 | Shaders 引擎与组件采用 MIT, 完整声明见 `public/third-party-licenses.txt` |

## 动态艺术生命周期

- 首屏演示进入视口后按需加载 WebGPU 引擎
- 系统减少动态效果、省流量与 WebGPU 能力状态决定静态降级
- 页面隐藏、演示离屏或用户暂停时停止动画
- 渲染尺寸按最长边 520 CSS px 设定, 内部像素密度遵循引擎设备上限
- GPU 初始化失败或设备丢失时显示 CSS 静态艺术
- 页面退出释放渲染器, 浏览器往返缓存恢复时继续同步播放状态
- `disableTelemetry: true` 关闭引擎遥测

## 设计决策

官网直接使用 Shaders 的 MIT 组件引擎. 官方 CLI 支持自然语言搜索、预览、编辑器项目同步, MCP 支持同类设计工作流; 官网使用独立配色与组件配置, 依赖仅限固定版本的 npm 包

实际运行官方 CLI `search 'iridescent glass floating spectral light' --limit 4 --json`, 成功返回 Floating Glass 7、2、3、4 预设. 预设与编辑器遵循独立服务条款, 官网当前采用 MIT 组件自行组合的视觉

Shaders 为 WebGPU 引擎, 浏览器能力决定动态效果是否启用. 图片与文字示意、下载入口与页面内容采用 HTML 与 CSS, 静态页面保持完整

动态引擎拆分为按需加载文件, 压缩后约 726 kB. 页面主交互压缩后约 3 kB, 首次 HTML 与 CSS 优先呈现

## 验证

```sh
node --check main.js
npm run build
```

浏览器验收覆盖桌面与窄屏布局、面板拖动与方向键移动、关闭与重置、暂停动画、下载入口与静态降级
