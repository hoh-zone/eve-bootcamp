/**
 * Bilingual nav: jump to the same page in the other language (en <-> zh).
 * Handles /prefix/en/..., /prefix/zh/..., and bare /prefix/en or /prefix/zh (no trailing path).
 */
(function () {
  function normalizePathname(path) {
    if (!path || path === "/") return "/";
    if (path.length > 1 && path.endsWith("/")) {
      return path.slice(0, -1);
    }
    return path;
  }

  function resolveSibling() {
    var path = normalizePathname(window.location.pathname);

    // .../en[/...] or .../zh[/...] — last path segment before any file must be the lang code
    var m = path.match(/^(.*)\/(en|zh)(?:\/(.*))?$/);
    if (m) {
      var prefix = m[1];
      var lang = m[2];
      var rest = m[3];
      if (!rest || rest.length === 0) {
        rest = "index.html";
      }
      var other = lang === "en" ? "zh" : "en";
      var href = prefix + "/" + other + "/" + rest;
      return { href: href, targetLang: other };
    }

    // mdbook serve: book root is one language; no /en/ or /zh/ in pathname
    var htmlLang = (document.documentElement.lang || "en").toLowerCase();
    var fromEn = htmlLang.indexOf("zh") === -1;
    var other = fromEn ? "zh" : "en";
    var tail = path.replace(/^\/+/, "");
    if (!tail) {
      tail = "index.html";
    }
    return { href: "../" + other + "/" + tail, targetLang: other };
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
