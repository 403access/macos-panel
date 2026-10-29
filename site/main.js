(function () {
  document.documentElement.classList.add("js");

  var year = document.getElementById("year");
  if (year) year.textContent = String(new Date().getFullYear());

  var reduce = window.matchMedia("(prefers-reduced-motion: reduce)").matches;
  var items = document.querySelectorAll(".reveal");

  if (reduce || !("IntersectionObserver" in window)) {
    items.forEach(function (el) {
      el.classList.add("in");
    });
  } else {
    var io = new IntersectionObserver(
      function (entries) {
        entries.forEach(function (entry) {
          if (!entry.isIntersecting) return;
          entry.target.classList.add("in");
          io.unobserve(entry.target);
        });
      },
      { rootMargin: "0px 0px -8% 0px", threshold: 0.1 }
    );
    items.forEach(function (el) {
      io.observe(el);
    });
  }

  document.querySelectorAll("[data-copy]").forEach(function (button) {
    button.addEventListener("click", function () {
      var target = document.querySelector(button.getAttribute("data-copy"));
      if (!target) return;
      var text = target.innerText;
      var done = function () {
        var label = button.textContent;
        button.textContent = "Copied";
        setTimeout(function () {
          button.textContent = label;
        }, 1600);
      };
      if (navigator.clipboard && navigator.clipboard.writeText) {
        navigator.clipboard.writeText(text).then(done, function () {});
      } else {
        var area = document.createElement("textarea");
        area.value = text;
        document.body.appendChild(area);
        area.select();
        try {
          document.execCommand("copy");
          done();
        } catch (e) {}
        document.body.removeChild(area);
      }
    });
  });
})();
