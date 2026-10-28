# README 与项目介绍官网

日期：2026-10-28

## 范围与事实审计

用户要求更新项目 README 并制作介绍官网。根目录尚无 README；工作树开始时干净。AGENTS.md 的 2026-09-17 状态已落后于开发状态中的 Web 生活领域、任务邀请、到期指标及 v0.2.1 发布记录；本次公开介绍采用最新状态记录及代码，不复述旧缺口。默认此刻遵循 2026-10-27 后续确认。

## 页面与工程边界

- 使用现有 React/TypeScript/Vite，多页面入口 `/about/index.html`（访问 `/about/`），根路径继续承载已有 Web 应用。
- 中文、暖白/珊瑚色、轻量排版；介绍定位、事项/记账/打卡/纪念日、交接验收闭环、Android 与 Web 使用方法。
- 产品示意明确标注；不连接 API、不请求身份、不保存示例数据。功能切换仅切换介绍面板。
- 下载指向仓库 Releases，Web 入口使用同源根路径；不伪造用户评价、使用人数、截图或应用商店链接。
- 支持 320/360/393/412 与桌面宽度、键盘焦点、减少动态效果和语义结构。资源本地打包，无远程字体或图片依赖。
- README 包含准确能力、运行入口、技术栈、目录、验证命令、部署与验收边界。仅交付源码及本地构建，不推送或公开部署。

## 验收

Playwright 覆盖官网直达、功能切换、导航、窄屏、无 API 请求及原有应用入口保留；运行 Web typecheck/test/build 和部署/边界静态检查。未改业务 API/数据库/Android，本轮不重复这些领域的全量测试，不冒充真机或线上验收。

## 历史方案：gh-pages 发布（已由 main/docs 替代）

用户已授权提交代码及使用 GitHub Pages。新增独立官网构建（`dist-website`），Pages 根目录直接展示介绍页，资源使用相对 URL 兼容仓库子路径；只打包官网代码，不发布工作区应用。该模式的 Web 链接指向 `https://muyu.bkverse.space/`，现有同源 `/about/` 行为保持。用户随后指定自行设置 Pages；静态产物提交到 `gh-pages` 分支根目录，用户选择 Deploy from a branch 即可，不增加 Pages 工作流。保持仓库私有；Pages 设置权限不足或套餐不支持时如实记录，不自动更改可见性或购买套餐。

## 历史方案：main/website（已由 main/docs 替代）

用户要求静态页面也存放 main 并建立独立目录。选择 `website/` 作为只含生成文件的发布目录，源码继续位于 `web/src/website/`；`npm run export:website` 可重建该目录。现有 `docs/` 是工程资料，不能整体作为官网发布包。GitHub 分支发布只支持 `/` 和 `/docs`，因此提供手动触发的 Pages 工作流，只上传 `website/`；用户自行选择 GitHub Actions 来源并触发，不自动改 Pages 设置。旧 gh-pages 分支保留作为此前交付。

## 最终目录：main/docs 分支发布

按用户最新要求，静态首页放 `docs/index.html`，资源放 `docs/assets/`，删除 website/ 与手动 Pages 工作流。Pages 设置使用 main → /docs。原工程文档保留；`docs/_config.yml` 默认排除所有文件，只允许首页与 assets 进入 Jekyll 发布，不能添加绕过该过滤的 `.nojekyll`。导出先构建到独立临时产物目录，再更新指定首页与资源目录，禁止把 Vite emptyOutDir 指向 docs，以免删除工程文档。
