// Minimal typed subtitle with Hitokoto support
(function () {
  function q(sel) { return document.querySelector(sel); }
  function typeText(el, text, speed, startDelay, cb) {
    let i = 0;
    function step() {
      if (i <= text.length) {
        el.textContent = text.slice(0, i);
        i++;
        setTimeout(step, speed);
      } else if (cb) {
        cb();
      }
    }
    setTimeout(step, startDelay);
  }
  function backspace(el, speed, backDelay, cb) {
    let txt = el.textContent;
    function step() {
      if (txt.length > 0) {
        txt = txt.slice(0, -1);
        el.textContent = txt;
        setTimeout(step, speed);
      } else if (cb) {
        cb();
      }
    }
    setTimeout(step, backDelay);
  }

  function run(config) {
    var el = q(config.selector || '#hitokoto-subtitle');
    if (!el) return;

    var api = config.api || 'https://v1.hitokoto.cn/?c=d&c=i';
    var typingSpeed = Number(config.typing_speed || 100);
    var backingSpeed = Number(config.backing_speed || 80);
    var startingDelay = Number(config.starting_delay || 500);
    var backingDelay = Number(config.backing_delay || 1500);
    var loop = String(config.loop).toLowerCase() === 'true';
    var showAuthor = String(config.show_author).toLowerCase() === 'true';

    function formatItem(item) {
      var text = item.hitokoto || '';
      var author = '';
      if (showAuthor) {
        var fromWho = item.from_who ? (' · ' + item.from_who) : '';
        var from = item.from ? ('《' + item.from + '》') : '';
        author = ' ' + [from, fromWho].filter(Boolean).join('');
      }
      return text + author;
    }

    function fetchAndType() {
      fetch(api, { cache: 'no-store' })
        .then(function (r) { return r.json(); })
        .then(function (data) {
          var text = formatItem(data);
          typeText(el, text, typingSpeed, startingDelay, function () {
            if (loop) {
              backspace(el, backingSpeed, backingDelay, fetchAndType);
            }
          });
        })
        .catch(function () {
          // Fallback: keep existing content or use first fallback text
          var fallback = (config.texts || '').split('|').filter(Boolean);
          var text = fallback[0] || el.textContent || '';
          typeText(el, text, typingSpeed, startingDelay, function () {
            if (loop) {
              backspace(el, backingSpeed, backingDelay, fetchAndType);
            }
          });
        });
    }

    fetchAndType();
  }

  // auto init from script tag dataset
  var s = document.currentScript;
  if (s && s.dataset) {
    run(s.dataset);
  }
})();

