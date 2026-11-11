# 四圣心源 · 存档生成流程

本书存档由 epub 单一来源生成，目录结构与 `yixuezhongzhongcanxilu` 完全一致。

## 来源

    _source/sishengxinyuan.epub     EPUB 原始文件（保留溯源，不参与部署）

## 生成

```powershell
# 干跑（只报告，不写盘）
.\scripts\sisheng-rebuild.ps1

# 正式生成
.\scripts\sisheng-rebuild.ps1 -Apply
```

流水线：

    _source/sishengxinyuan.epub
      → 解包到临时目录
      → epub-parse-ncx.ps1 解析 toc.ncx → _toc.json（临时）
      → sisheng-build.ps1 渲染 189 个章节页 + index.html + static/js/catalog.js
      → 清理中间产物

## 校验

```powershell
.\scripts\sisheng-verify.ps1          # 目录可达性：189/189，0 孤儿，0 断链
.\scripts\check-case-sensitivity.ps1 -Root .   # Linux 部署前必备
.\scripts\scan-encoding.ps1 -Root .zysj\sishengxinyuan
```

## 页面文件命名

    EPUB  1296/13.htm   →   1296-13.html

`1296` 为源站书籍编号，`13` 为章节序号。共 189 个页面（EPUB spine 190 项，titlepage 除外）。

## 全本页 quanben.html

- 与 `yixuezhongzhongcanxilu/quanben.html` 同构：`<div class="section" id="ciN">` + `<h2/h3 class="title">`
- 189 个章节全部展开，`#main` 带 `content all page` 三个类
- 面包屑：首页 / 中医书籍 / 《四圣心源》，其后是 `<h1>《四圣心源》<small>(全本)</small></h1>`
- 侧栏内嵌（非 catalog.js）且 `data-get="q"`，点目录项在本页内跳转到 `#ciN`
- 共享 `css.css` 中的 `#content>div.section{content-visibility:auto}` 在此页生效，
  视口外章节跳过布局，长页面滚动更流畅

入口：
- `index.html` 的 `catalog-info` 区 → 「全部内容 (不分页)」
- 每个章节页面包屑 → 「全部内容」

## 侧栏目录

- `static/js/catalog.js` 注入 `<div id="sidebar">`，189 页共用一份
- 目录层级来自 `toc.ncx`：卷一~卷十为分卷（`<span>`），其下为章节
- 分卷自身若有独立页面，会作为该分卷的第一个子链接出现，避免页面不可达
- 当前章节高亮与自动滚动由 `static/js/js.js` 按 URL 匹配

## 与模板书的差异

| 项目 | 处理方式 |
|---|---|
| 全书不分页页（`quanben.html`） | 已生成，格式与模板书同构；`content-visibility` 由共享 CSS 自动生效 |
| `index1.html` / `index2.html` | 本书未提供，面包屑与顶栏导航统一改指 `../index.html`（经书导航） |
| 书名 | 模板中的《医学衷中参西录》全局替换为《四圣心源》 |
