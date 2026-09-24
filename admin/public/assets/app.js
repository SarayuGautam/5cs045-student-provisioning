// 5CS045 admin panel. Small enhancements only: every page also works as plain links and forms.
'use strict';

const $ = (sel, root = document) => root.querySelector(sel);
const $$ = (sel, root = document) => Array.from(root.querySelectorAll(sel));

document.addEventListener('DOMContentLoaded', () => {
  enhance(document);
  roster();
  autoSubmit();
  countEmails();
  jobLog();
});

// Everything inside a piece of page that can be swapped in (the student panel)
function enhance(root) {
  meters(root);
  busyForms(root);
  confirmInputs(root);
  copyButtons(root);
  flashes(root);
  emailCheckboxes(root);
  fillChips(root);
}

// Usage bars take their width from data-pct (the page's security policy blocks inline styles)
function meters(root) {
  const bars = $$('[data-pct]', root);
  requestAnimationFrame(() => requestAnimationFrame(() => bars.forEach((el) => {
    el.style.width = `${Math.min(100, Math.max(0, +el.dataset.pct))}%`;
  })));
}

// Shows that something is happening, and stops a second click sending the form twice
function busyForms(root) {
  $$('form[data-busy]', root).forEach((form) => form.addEventListener('submit', (e) => {
    if (form.dataset.sending) { e.preventDefault(); return; }
    form.dataset.sending = '1';
    const btn = e.submitter || $('button[type=submit]', form);
    if (!btn) return;
    if (btn.dataset.busyText) {
      const label = $('span', btn) || [...btn.childNodes].reverse().find((n) => n.nodeType === 3 && n.textContent.trim());
      if (label) label.textContent = btn.dataset.busyText;
    }
    btn.classList.add('is-busy');
    setTimeout(() => { btn.disabled = true; }, 0); // after the browser has read the form
  }));
}
window.addEventListener('pageshow', (e) => {
  if (!e.persisted) return; // back button: do not leave buttons stuck
  $$('form[data-sending]').forEach((f) => delete f.dataset.sending);
  $$('.is-busy').forEach((b) => { b.classList.remove('is-busy'); b.disabled = false; });
});

// "Type the username to confirm": the button only wakes up once it matches
function confirmInputs(root) {
  $$('input[data-confirm]', root).forEach((input) => {
    const btn = $('button[type=submit]', input.form);
    const check = () => { btn.disabled = input.value.trim() !== input.dataset.confirm; };
    input.addEventListener('input', check);
    check();
  });
}

function copyButtons(root) {
  $$('[data-copy]', root).forEach((btn) => btn.addEventListener('click', async () => {
    const src = $(btn.dataset.copy);
    if (!src) return;
    try {
      await navigator.clipboard.writeText(src.textContent.trim());
    } catch {
      const range = document.createRange();
      range.selectNodeContents(src);
      getSelection().removeAllRanges();
      getSelection().addRange(range);
      document.execCommand('copy');
    }
    const label = $('span', btn);
    clearTimeout(btn.copyTimer);
    btn.classList.add('is-done');
    if (label) {
      label.dataset.was ??= label.textContent;
      label.textContent = 'Copied';
    } else {
      btn.setAttribute('aria-label', 'Copied');
    }
    btn.copyTimer = setTimeout(() => {
      btn.classList.remove('is-done');
      if (label) label.textContent = label.dataset.was;
    }, 1600);
  }));
}

function flashes(root) {
  const leave = (f) => {
    f.classList.add('is-leaving');
    setTimeout(() => f.remove(), 180);
  };
  $$('[data-dismiss]', root).forEach((b) => b.addEventListener('click', () => leave(b.closest('.flash'))));
  // Confirmations tidy themselves away; errors stay until dismissed
  $$('.flashes .flash-success', root).forEach((f) => setTimeout(() => f.isConnected && leave(f), 7000));
}

// "Email them their login" needs an email address to send to
function emailCheckboxes(root) {
  $$('[data-needs-email]', root).forEach((box) => {
    const email = $('[data-email-source]', box.form);
    if (!email) return;
    const hint = $('[data-needs-email-hint]', box.form);
    let wanted = box.checked; // what the admin chose, kept while the box is switched off
    box.addEventListener('change', () => { wanted = box.checked; });
    const sync = () => {
      const has = email.value.trim() !== '';
      box.disabled = !has;
      box.checked = has && wanted;
      box.closest('.check').classList.toggle('is-off', !has);
      if (hint) hint.hidden = has;
    };
    email.addEventListener('input', sync);
    sync();
  });
  $$('[data-toggles]', root).forEach((box) => {
    const target = document.getElementById(box.dataset.toggles);
    if (!target) return;
    const sync = () => {
      target.hidden = !box.checked;
      $$('input', target).forEach((i) => { i.required = box.checked; });
    };
    box.addEventListener('change', sync);
    sync();
  });
}

function fillChips(root) {
  $$('[data-fill-target]', root).forEach((group) => {
    const input = $(`input[name="${group.dataset.fillTarget}"]`, group.closest('form'));
    $$('[data-fill]', group).forEach((chip) => chip.addEventListener('click', () => {
      input.value = chip.dataset.fill;
      input.focus();
    }));
  });
}

function autoSubmit() {
  $$('select[data-autosubmit]').forEach((s) => s.addEventListener('change', () => s.form.requestSubmit()));
}

function countEmails() {
  $$('[data-count-for]').forEach((out) => {
    const area = document.getElementById(out.dataset.countFor);
    const sync = () => {
      const n = area.value.split(/[\s,;]+/).filter((x) => x.includes('@')).length;
      out.textContent = n ? `(${n})` : '';
    };
    area.addEventListener('input', sync);
    sync();
  });
}

// ---------------------------------------------------------------------------------------------
// The roster: type to find, arrow keys to move, Enter to open. The student opens beside the
// list without reloading it, so the list keeps its place.

function roster() {
  const finder = $('[data-finder]');
  const list = $('[data-people]');
  const panel = $('[data-panel]');
  if (!finder || !list || !panel) return;
  const people = $$('.person', list);
  const none = $('.people-none');
  const wide = matchMedia('(min-width: 901px)');
  let cursor = null;

  const visible = () => people.filter((p) => !p.parentElement.hidden);
  const setCursor = (p) => {
    cursor?.classList.remove('is-cursor');
    cursor = p;
    if (p) {
      p.classList.add('is-cursor');
      p.scrollIntoView({ block: 'nearest' });
    }
  };

  const filter = () => {
    const words = finder.value.toLowerCase().split(/\s+/).filter(Boolean);
    let shown = 0;
    people.forEach((p) => {
      const ok = words.every((w) => p.dataset.search.includes(w));
      p.parentElement.hidden = !ok;
      if (ok) shown++;
    });
    if (none) none.hidden = shown > 0;
    setCursor(words.length ? visible()[0] || null : null);
  };
  finder.addEventListener('input', filter);
  $('[data-clear]')?.addEventListener('click', () => { finder.value = ''; filter(); finder.focus(); });

  finder.addEventListener('keydown', (e) => {
    const vis = visible();
    const i = cursor ? vis.indexOf(cursor) : -1;
    if (e.key === 'ArrowDown') { e.preventDefault(); setCursor(vis[Math.min(i + 1, vis.length - 1)] || null); }
    else if (e.key === 'ArrowUp') { e.preventDefault(); setCursor(vis[Math.max(i - 1, 0)] || null); }
    else if (e.key === 'Enter' && cursor) { e.preventDefault(); open(cursor, false); }
    else if (e.key === 'Escape') { finder.value = ''; filter(); }
  });

  // "/" from anywhere jumps to the search box
  document.addEventListener('keydown', (e) => {
    if (e.key === '/' && !e.target.closest('input, textarea, select, [contenteditable]')) {
      e.preventDefault();
      finder.focus();
      finder.select();
    }
  });

  list.addEventListener('click', (e) => {
    const p = e.target.closest('.person');
    if (!p || e.metaKey || e.ctrlKey || e.shiftKey || e.button !== 0) return;
    e.preventDefault();
    open(p, true);
  });

  // Swap the panel in place. Animated for a click, instant for the keyboard (it is repeated a lot).
  let request = 0;
  async function open(p, animate) {
    if (!wide.matches) { location.href = p.href; return; }
    const mine = ++request;
    people.forEach((x) => { x.classList.toggle('is-selected', x === p); x.removeAttribute('aria-current'); });
    p.setAttribute('aria-current', 'true');
    setCursor(p);
    try {
      const r = await fetch(p.href, { headers: { 'X-Panel': '1' } });
      if (r.redirected || r.status === 401) { location.href = r.url; return; }
      const html = await r.text();
      if (mine !== request) return;
      showPanel(html, animate);
      history.pushState({ panel: p.href }, '', p.href);
      document.title = `${p.querySelector('.person-meta .mono').textContent} - 5CS045 admin`;
    } catch {
      location.href = p.href;
    }
  }

  function showPanel(html, animate) {
    panel.innerHTML = html;
    const body = $('.panel-body', panel);
    if (animate && body) { // with reduced motion the CSS turns this into a plain fade
      body.classList.add('is-entering');
      body.addEventListener('animationend', () => body.classList.remove('is-entering'), { once: true });
    }
    panel.scrollTop = 0;
    enhance(panel);
  }

  window.addEventListener('popstate', async () => {
    if (!wide.matches) { location.reload(); return; }
    const url = location.pathname;
    people.forEach((x) => x.classList.toggle('is-selected', x.pathname === url));
    try {
      const r = await fetch(url, { headers: { 'X-Panel': '1' } });
      showPanel(await r.text(), false);
    } catch {
      location.reload();
    }
  });
}

// ---------------------------------------------------------------------------------------------
// A background job's live output

function jobLog() {
  const card = $('[data-job]');
  if (!card) return;
  const log = $('#job-log');
  const state = $('[data-job-state]');
  const summary = $('[data-job-summary]');

  const paint = (text) => {
    const atBottom = log.scrollHeight - log.scrollTop - log.clientHeight < 40;
    const frag = document.createDocumentFragment();
    text.split('\n').forEach((line, i, all) => {
      const span = document.createElement('span');
      if (/^\s*(PASS|ADDED)\b|Looks safe/.test(line)) span.className = 'ln-ok';
      else if (/^\s*(FAIL|FAILED|ERROR)\b|DO NOT|email FAILED/.test(line)) span.className = 'ln-bad';
      else if (/^===|^\s*\d+ passed|^Done:|^Removed \d+/.test(line)) span.className = 'ln-head';
      span.textContent = line + (i < all.length - 1 ? '\n' : '');
      frag.appendChild(span);
    });
    log.replaceChildren(frag);
    if (atBottom) log.scrollTop = log.scrollHeight;
  };

  const summarise = (job) => {
    const text = job.log || '';
    const smoke = text.match(/(\d+) passed, (\d+) failed/);
    const added = text.match(/Done: (\d+) added, (\d+) skipped, (\d+) failed/);
    const removed = text.match(/Removed (\d+) student\(s\)\. Failed: (\d+)/);
    if (smoke) return +smoke[2] === 0 ? `All ${smoke[1]} checks passed.` : `${smoke[2]} of ${+smoke[1] + +smoke[2]} checks failed. Fix those before giving out accounts.`;
    if (added) return `${added[1]} added, ${added[2]} skipped, ${added[3]} failed.`;
    if (removed) return `${removed[1]} removed, ${removed[2]} failed.`;
    return job.exit === 0 ? 'Finished.' : `Finished with exit code ${job.exit}.`;
  };

  paint(log.textContent);
  log.scrollTop = log.scrollHeight;
  const url = location.pathname + '.json';

  if (card.dataset.done === '1') {
    fetch(url).then((r) => r.json()).then((job) => { if (job.done) summary.textContent = summarise(job); }).catch(() => {});
    return;
  }

  let delay = 1000;
  const tick = async () => {
    try {
      const r = await fetch(url);
      if (r.status === 401) { location.href = '/login'; return; }
      const job = await r.json();
      if (job.log !== log.textContent) paint(job.log);
      delay = 1000;
      if (job.done) {
        const [cls, label] = job.state;
        state.className = `state state-${cls}`;
        state.textContent = label;
        summary.textContent = summarise(job);
        return;
      }
    } catch {
      delay = Math.min(delay * 2, 8000); // PHP reloads at the end of some jobs; keep trying
    }
    setTimeout(tick, delay);
  };
  setTimeout(tick, delay);
}
