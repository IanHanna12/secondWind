/* ==========================================================================
   Second Wind — site interactions
   ========================================================================== */

(function () {
  "use strict";

  /* ---------- Sticky nav + scroll progress ---------- */
  var nav = document.getElementById("nav");
  var scrollBar = document.getElementById("scrollBar");
  var scrollUpdatePending = false;

  function updateScrollUI() {
    var y = window.scrollY || document.documentElement.scrollTop;
    if (nav) nav.classList.toggle("is-scrolled", y > 10);

    var doc = document.documentElement;
    var max = doc.scrollHeight - window.innerHeight;
    var progress = max > 0 ? Math.min(Math.max(y / max, 0), 1) : 0;
    if (scrollBar) scrollBar.style.transform = "scaleX(" + progress + ")";
    scrollUpdatePending = false;
  }

  function requestScrollUpdate() {
    if (scrollUpdatePending) return;
    scrollUpdatePending = true;
    window.requestAnimationFrame(updateScrollUI);
  }

  window.addEventListener("scroll", requestScrollUpdate, { passive: true });
  window.addEventListener("resize", requestScrollUpdate, { passive: true });
  requestScrollUpdate();

  /* ---------- Mobile menu ---------- */
  var toggle = document.getElementById("navToggle");
  var links = document.getElementById("navLinks");

  if (toggle && links) {
    function closeMenu() {
      links.classList.remove("is-open");
      toggle.setAttribute("aria-expanded", "false");
    }

    toggle.addEventListener("click", function () {
      var open = links.classList.toggle("is-open");
      toggle.setAttribute("aria-expanded", open ? "true" : "false");
      if (open) {
        var first = links.querySelector("a");
        if (first) first.focus();
      } else {
        toggle.focus();
      }
    });

    // Close after navigating
    links.addEventListener("click", function (e) {
      if (e.target.tagName === "A") {
        closeMenu();
      }
    });

    document.addEventListener("keydown", function (e) {
      if (e.key === "Escape" && links.classList.contains("is-open")) {
        closeMenu();
        toggle.focus();
      }
    });
  }

  /* ---------- Scroll reveal ---------- */
  var revealEls = document.querySelectorAll(".reveal");

  if ("IntersectionObserver" in window) {
    var io = new IntersectionObserver(
      function (entries) {
        entries.forEach(function (entry) {
          if (entry.isIntersecting) {
            var el = entry.target;
            el.classList.add("in");
            io.unobserve(el);

            // Release the stagger delay once revealed, so hover
            // transitions on the element are not held back afterwards.
            function releaseDelay(e) {
              if (e.propertyName === "opacity") {
                el.removeEventListener("transitionend", releaseDelay);
                el.style.removeProperty("--delay");
              }
            }
            el.addEventListener("transitionend", releaseDelay);
          }
        });
      },
      { threshold: 0.12, rootMargin: "0px 0px -40px 0px" }
    );

    revealEls.forEach(function (el) {
      // Subtle stagger, relative to the element's own sibling group
      var parent = el.closest(".grid, .principles, .privacy__list, .strip ul");
      if (parent) {
        var siblings = Array.prototype.slice.call(parent.querySelectorAll(".reveal"));
        var idx = siblings.indexOf(el);
        el.style.setProperty("--delay", (idx * 0.07).toFixed(2) + "s");
      }
      io.observe(el);
    });
  } else {
    revealEls.forEach(function (el) { el.classList.add("in"); });
  }

  /* ---------- Screenshot tabs ---------- */
  var tabs = Array.prototype.slice.call(document.querySelectorAll(".tab"));
  var panels = Array.prototype.slice.call(document.querySelectorAll("[data-shot-panel]"));

  function activateTab(name) {
    tabs.forEach(function (t) {
      var active = t.dataset.shot === name;
      t.classList.toggle("is-active", active);
      t.setAttribute("aria-selected", active ? "true" : "false");
      t.tabIndex = active ? 0 : -1;
    });
    panels.forEach(function (p) {
      var active = p.id === "shot-" + name;
      p.classList.toggle("is-active", active);
      p.hidden = !active;
    });
  }

  tabs.forEach(function (t) {
    t.addEventListener("click", function () { activateTab(t.dataset.shot); });
  });

  // Arrow-key navigation between tabs (ARIA tabs pattern)
  var tablist = document.querySelector(".tabs__bar");
  if (tablist) {
    tablist.addEventListener("keydown", function (e) {
      var current = tablist.querySelector(".tab.is-active");
      var all = Array.prototype.slice.call(tablist.querySelectorAll(".tab"));
      var idx = all.indexOf(current);
      var next = null;

      if (e.key === "ArrowRight" || e.key === "ArrowDown") {
        next = all[(idx + 1) % all.length];
      } else if (e.key === "ArrowLeft" || e.key === "ArrowUp") {
        next = all[(idx - 1 + all.length) % all.length];
      } else if (e.key === "Home") {
        next = all[0];
      } else if (e.key === "End") {
        next = all[all.length - 1];
      }

      if (next) {
        e.preventDefault();
        next.click();
        next.focus();
      }
    });
  }

  /* ---------- Copy-to-clipboard ---------- */
  var copyBtns = document.querySelectorAll("[data-copy]");

  copyBtns.forEach(function (copyBtn) {
    copyBtn.addEventListener("click", function () {
      var code = document.getElementById(copyBtn.dataset.copyTarget);
      if (!code) return;

      var text = code.textContent.trim() + "\n";
      var done = function () {
        var label = copyBtn.querySelector("span");
        var original = label ? label.textContent : "Copy";
        if (label) label.textContent = "Copied!";
        setTimeout(function () {
          if (label) label.textContent = original;
        }, 1800);
      };

      if (navigator.clipboard && navigator.clipboard.writeText) {
        navigator.clipboard.writeText(text).then(done).catch(function () {
          fallbackCopy(text);
          done();
        });
      } else {
        fallbackCopy(text);
        done();
      }
    });
  });

  function fallbackCopy(text) {
    var ta = document.createElement("textarea");
    ta.value = text;
    ta.style.position = "fixed";
    ta.style.opacity = "0";
    document.body.appendChild(ta);
    ta.select();
    try { document.execCommand("copy"); } catch (e) { /* noop */ }
    document.body.removeChild(ta);
  }

  /* ---------- Footer year ---------- */
  var yearEl = document.getElementById("year");
  if (yearEl) yearEl.textContent = new Date().getFullYear();
})();
