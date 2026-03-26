/**
 * Bilingual nav: jump to the same page in the other language (en <-> zh).
 * Works when the site is served as book/en/... and book/zh/..., or when each
 * book is served with mdbook serve (flat paths under one language root).
 */
(function () {
  function resolveSibling() {
    var path = window.location.pathname;
    var m = path.match(/^(.*)\/(en|zh)\/(.+)$/);
    if (m) {
      var prefix = m[1];
      var lang = m[2];
      var rest = m[3];
      var other = lang === "en" ? "zh" : "en";
      return { href: prefix + "/" + other + "/" + rest, targetLang: other };
    }
    var htmlLang = (document.documentElement.lang || "en").toLowerCase();
    var fromEn = htmlLang.indexOf("zh") === -1;
    var other = fromEn ? "zh" : "en";
    var parts = path.split("/").filter(Boolean);
    var file = parts.length ? parts[parts.length - 1] : "index.html";
    if (!file) file = "index.html";
    return { href: "../" + other + "/" + file, targetLang: other };
  }

  function run() {
    var bar = document.querySelector("#mdbook-menu-bar .right-buttons");
    if (!bar) return;

    var r = resolveSibling();
    if (!r || !r.href) return;

    var wrap = document.createElement("span");
    wrap.className = "eve-lang-switch";
    wrap.setAttribute("title", "Switch language / 切换语言");

    var a = document.createElement("a");
    a.href = r.href;
    a.className = "eve-lang-switch-link";
    a.setAttribute("rel", "alternate");
    a.setAttribute("hreflang", r.targetLang === "zh" ? "zh-CN" : "en");
    a.textContent = r.targetLang === "zh" ? "中文" : "English";
    a.setAttribute("aria-label", r.targetLang === "zh" ? "Switch to Chinese" : "Switch to English");

    wrap.appendChild(a);
    bar.insertBefore(wrap, bar.firstChild);
  }

  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", run);
  } else {
    run();
  }
})();
