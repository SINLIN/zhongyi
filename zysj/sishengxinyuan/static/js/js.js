/* 存档阅读增强：目录定位、全书跳转（精简版，替代原站 44KB 混淆脚本） */
(function () {
    'use strict';

    /* 防止被第三方页面嵌套 */
    try {
        if (window.top && window.top !== window.self && window.top.location) {
            window.top.location.replace(location.href);
        }
    } catch (e) { }

    /* 当前章目录项距目录滚动框顶部的偏移（保持与原站一致的视觉位置） */
    var OFFSET = 54;

    function init() {
        var guide = document.getElementById('guide');
        if (!guide) { return; }

        var file = (location.pathname.split('/').pop() || '');
        var target = file.replace(/_group\.html$/i, '.html');
        var isGroup = target !== file;

        var links = guide.getElementsByTagName('A');
        var cur = null, i, a, href, base, isGroupLink;

        for (i = 0; i < links.length; i++) {
            a = links[i];
            href = a.getAttribute('href') || '';
            if (!href || href.charAt(0) === '#') { continue; }
            isGroupLink = (' ' + a.className + ' ').indexOf(' catalog_group ') !== -1;
            if (isGroupLink) { continue; }
            base = href.split('#')[0].split('/').pop();
            if (base === target) { cur = a; break; }
        }

        /* 组合页若没有正文章节链接，则高亮其“节”入口 */
        if (!cur && isGroup) {
            for (i = 0; i < links.length; i++) {
                a = links[i];
                href = a.getAttribute('href') || '';
                if (!href || href.charAt(0) === '#') { continue; }
                if ((' ' + a.className + ' ').indexOf(' catalog_group ') === -1) { continue; }
                base = href.split('#')[0].split('/').pop();
                if (base === file) { cur = a; break; }
            }
        }

        if (cur) {
            cur.className = (cur.className ? cur.className + ' ' : '') + 'now';
            if (isGroup && cur.parentNode && cur.parentNode.nodeType === 1) {
                cur.parentNode.className = (cur.parentNode.className ? cur.parentNode.className + ' ' : '') + 'now';
            }
            /* 自动把当前章节滚动到目录可视区，替代原「定位」按钮 */
            var gr = guide.getBoundingClientRect();
            var ar = cur.getBoundingClientRect();
            var rel = (ar.top - gr.top) + guide.scrollTop;
            guide.scrollTop = Math.max(0, rel - OFFSET);
        }

        /* 全书不分页模式：点击目录在页内跳转 */
        if (guide.getAttribute('data-get') === 'q') {
            guide.addEventListener('click', function (ev) {
                var n = ev.target;
                while (n && n !== guide && n.nodeName !== 'A') { n = n.parentNode; }
                if (!n || n.nodeName !== 'A') { return; }
                var li = n.parentNode;
                var id = li && li.id;
                if (!id || id.indexOf('si') !== 0) { return; }
                var t = document.getElementById('ci' + id.slice(2));
                if (t) { ev.preventDefault(); t.scrollIntoView(true); }
            }, false);
        }
    }

    if (document.readyState === 'loading') {
        document.addEventListener('DOMContentLoaded', init, false);
    } else {
        init();
    }
})();
