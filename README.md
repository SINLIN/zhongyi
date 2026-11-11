# zhongyi — 中医书籍静态存档

四部中医典籍的离线存档站点，纯静态 HTML，通过 Cloudflare Workers Static Assets
从 GitHub 构建部署。

## 目录结构

    index.html                站点根：404 占位页（防爬虫/探测，不含任何真实路径）
    404.html                  not_found_handling 使用的错误页
    robots.txt                全站 Disallow，屏蔽搜索引擎与 AI 爬虫
    _headers                  Workers 响应头（缓存 + 安全）
    wrangler.jsonc            Workers 部署配置
    .assetsignore             不参与部署的文件（.git、scripts、*.z、*.zip）
    .gitattributes            统一 LF 换行、二进制类型声明
    .gitignore                忽略抓取缓存与临时文件

    zysj/
      index.html              真实入口：经书导航
      shanghanlun/            伤寒论
      shanghanzhabinglun/     伤寒杂病论
      jingyuequanshu/         景岳全书
      yixuezhongzhongcanxilu/ 医学衷中参西录

各书目录（HTTrack 镜像布局）：

    <书>/web/html/*.html      正文页
    <书>/web/js/js.js         阅读脚本（目录高亮 / 全书跳转）
    <书>/web/js/catalog.js    共享侧边栏目录（外置，避免每页重复 ~60 KB）
    <书>/web/css/css.css      样式

yixuezhongzhongcanxilu 使用 static/ 前缀，其余三本使用 web/ 前缀。

## 访问入口

| 路径 | 内容 |
| --- | --- |
| `/` | 404 占位页（noindex，不暴露任何内部路径） |
| `/zysj/` | 经书导航（真实入口） |
| `/zysj/shanghanlun/` | 伤寒论 |
| `/zysj/shanghanzhabinglun/web/html/` | 伤寒杂病论 |
| `/zysj/jingyuequanshu/web/html/` | 景岳全书 |
| `/zysj/yixuezhongzhongcanxilu/` | 医学衷中参西录 |

## 部署

    npx wrangler deploy

GitHub 连接 Cloudflare Workers Builds 时：Build command 留空，
Deploy command 使用 `npx wrangler deploy`。

wrangler.jsonc 为纯静态资源模式（无 Worker 脚本）。.assetsignore 会排除
.git/、scripts/、*.z、*.zip 等非站点内容。

## 维护脚本

| 脚本 | 用途 |
| --- | --- |
| scripts/clean-html-tracking.ps1 | 删除内联统计脚本，替换旧域名 |
| scripts/optimize-archive.ps1 | 侧栏外置 + 图标合并 + 精简 js.js + 渲染优化 |
| scripts/optimize-book-pages.ps1 | yixuezhongzhongcanxilu 专用 |
| scripts/optimize-jingyue.ps1 | jingyuequanshu 专用（含链接重写） |
| scripts/scan-encoding.ps1 | 检查编码 / BOM / 换行符（只读） |
| scripts/normalize-encoding.ps1 | 统一 UTF-8 无 BOM + LF |
| scripts/check-case-sensitivity.ps1 | 校验引用与文件名大小写是否严格一致 |

所有脚本默认干跑，加 -Apply 才写盘。

    # 优化某本书
    .\scripts\optimize-archive.ps1 -Root .\zysj\shanghanzhabinglun `
        -SlimJsSource .\zysj\yixuezhongzhongcanxilu\static\js\js.js -Apply

    # 部署前自检
    .\scripts\check-case-sensitivity.ps1 -Root .
    .\scripts\scan-encoding.ps1 -Root .

## 注意事项

- 换行符：仓库内统一 LF（.gitattributes 已锁定）。
- 编码：全部 UTF-8 无 BOM；唯一例外是 scripts/*.ps1 保留 BOM
  （Windows PowerShell 5.1 解码无 BOM 的中文脚本会乱码）。
- 大小写：Windows 不区分大小写，Workers（Linux）区分。
  改动链接后务必跑一次 check-case-sensitivity.ps1。
- 侧栏目录：catalog.js 由脚本生成，不要手工编辑。
- .z / .zip：HTTrack 抓取产物，已取消 Git 跟踪且不部署。

## 内容说明

本站为个人学习用中医典籍存档，内容来源为中医世家公开页面。
身体不适请就医，站内信息仅供参考。