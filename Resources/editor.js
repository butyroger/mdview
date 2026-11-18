// MDView 所見即所得編輯：#doc 設為 contenteditable，儲存時把 DOM 轉回 Markdown。
// 為了不弄亂沒動到的內容，渲染時每個最上層區塊包成 <div class="mdb" data-b=…> 並記住原始碼行；
// 儲存時沒改過的區塊原樣輸出，只有改過或新增的區塊才用 turndown 轉換。
const ED = { editing: false, dirty: false, text: '', nl: true, lead: [], blocks: new Map(), seq: 0 };
const $ = id => document.getElementById(id);
const post = m => { try { window.webkit.messageHandlers.mdview.postMessage(m); } catch (e) {} };

function renderBlocks(text) {
  ED.text = text; ED.nl = text === '' || text.endsWith('\n');
  const lines = (text.endsWith('\n') ? text.slice(0, -1) : text).split('\n');
  const env = {}, toks = md.parse(text, env), groups = [];
  for (let i = 0; i < toks.length; i++) {
    let j = i;
    if (toks[i].nesting === 1) for (let d = 0; j < toks.length; j++) { d += toks[j].nesting; if (d === 0) break; }
    groups.push({ a: i, b: j, map: toks[i].map || [0, 0] }); i = j;
  }
  ED.blocks = new Map();
  ED.lead = lines.slice(0, groups.length ? groups[0].map[0] : lines.length);
  let html = '', prev = null;
  groups.forEach((g, k) => {
    const id = 'b' + (++ED.seq), [s, e] = g.map;
    const nextS = k + 1 < groups.length ? groups[k + 1].map[0] : lines.length;
    ED.blocks.set(id, { src: lines.slice(s, e), gap: lines.slice(e, Math.max(e, nextS)), next: null });
    if (prev) ED.blocks.get(prev).next = id;
    prev = id;
    html += '<div class="mdb" data-b="' + id + '">' + md.renderer.render(toks.slice(g.a, g.b + 1), md.options, env) + '</div>';
  });
  return html;
}

const sig = el => el.tagName + '|' + el.innerHTML.replace(/ id="[^"]*"/g, '');
function snapshot() {
  document.querySelectorAll('#doc > [data-b]').forEach(el => { const b = ED.blocks.get(el.dataset.b); if (b) b.sig = sig(el); });
}
function setDirty(v) {
  if (ED.dirty === v) return;
  ED.dirty = v; post(v ? 'dirty' : 'clean');
  $('st').textContent = v ? '● 尚未儲存（⌘S）' : '';
}

// ---- HTML → Markdown ----
let _td;
function td() {
  if (_td) return _td;
  const t = new TurndownService({ headingStyle: 'atx', codeBlockStyle: 'fenced', bulletListMarker: '-', emDelimiter: '*', strongDelimiter: '**', hr: '---' });
  t.use(turndownPluginGfm.gfm);
  t.keep(['kbd', 'sup', 'sub', 'u', 'mark']);
  t.addRule('taskListItems', {
    filter: n => n.nodeName === 'INPUT' && n.type === 'checkbox' && n.parentNode.nodeName === 'LI',
    replacement: (c, n) => (n.hasAttribute('checked') || n.checked ? '[x]' : '[ ]') + ' '
  });
  t.addRule('listItem', {
    filter: 'li',
    replacement(content, node, o) {
      const parent = node.parentNode;
      let prefix = o.bulletListMarker + ' ';
      if (parent.nodeName === 'OL') {
        const start = parent.getAttribute('start'), idx = Array.prototype.indexOf.call(parent.children, node);
        prefix = (start ? Number(start) + idx : idx + 1) + '. ';
      }
      content = content.replace(/^\n+/, '').replace(/\n+$/, '\n').replace(/^\[( |x)\]\s+/, '[$1] ')
        .replace(/\n/gm, '\n' + ' '.repeat(prefix.length));
      return prefix + content + (node.nextSibling && !/\n$/.test(content) ? '\n' : '');
    }
  });
  t.addRule('preNoCode', {
    filter: n => n.nodeName === 'PRE' && !(n.firstChild && n.firstChild.nodeName === 'CODE'),
    replacement: (c, n) => '\n\n```\n' + n.textContent.replace(/\n$/, '') + '\n```\n\n'
  });
  return (_td = t);
}
function normalizeLists(root) {
  // WebKit 縮排清單會產生 <ul><li>a</li><ul>…</ul></ul>，改成合法的巢狀
  root.querySelectorAll('ul > ul, ul > ol, ol > ul, ol > ol').forEach(l => {
    const li = l.previousElementSibling;
    if (li && li.nodeName === 'LI') li.appendChild(l);
  });
  // markdown-it 用 style 標對齊，turndown-gfm 只看 align 屬性
  root.querySelectorAll('th[style],td[style]').forEach(c => { if (c.style.textAlign) c.setAttribute('align', c.style.textAlign); });
  root.querySelectorAll('mark.hit').forEach(m => m.replaceWith(m.textContent));
}
function toMd(n) {
  const box = document.createElement('div');
  if (n.nodeType === 3) { const p = document.createElement('p'); p.textContent = n.nodeValue; box.appendChild(p); }
  else box.appendChild(n.cloneNode(true));
  normalizeLists(box);
  return td().turndown(box).replace(/\s+$/, '');
}

function getMarkdown(commit) {
  clearHits();
  if (!ED.dirty) return ED.text;
  const doc = $('doc'), pieces = [], used = new Set();
  for (const n of Array.from(doc.childNodes)) {
    if (n.nodeType === 3 ? !n.nodeValue.trim() : n.nodeType !== 1) continue;
    const id = n.nodeType === 1 ? n.dataset.b : null;
    const b = id && !used.has(id) ? ED.blocks.get(id) : null;
    if (b) used.add(id);
    if (b && b.sig === sig(n)) { pieces.push({ node: n, src: b.src, orig: true, b, id }); continue; }
    const m = toMd(n);
    if (!m.trim()) continue;
    pieces.push({ node: n, src: m.split('\n'), orig: false, b, id: b ? id : null });
  }
  const out = ED.lead.slice();
  pieces.forEach((p, k) => {
    if (!p.orig) { while (out.length && !out[out.length - 1].trim()) out.pop(); if (out.length) out.push(''); }
    p.start = out.length; out.push(...p.src); p.end = out.length;
    const nxt = pieces[k + 1];
    let gap = p.b ? p.b.gap.slice() : [];
    const contiguous = p.orig && nxt && nxt.orig && p.b.next === nxt.id;
    if (nxt && !contiguous) {
      if (!gap.length || gap[0].trim()) gap.unshift('');
      if (gap[gap.length - 1].trim()) gap.push('');
    }
    out.push(...gap);
  });
  const last = pieces[pieces.length - 1];
  if (!last || !last.orig) while (out.length && !out[out.length - 1].trim()) out.pop();
  const text = out.join('\n') + (ED.nl && out.length ? '\n' : '');
  if (commit) {
    ED.text = text;
    ED.lead = out.slice(0, pieces.length ? pieces[0].start : out.length);
    ED.blocks = new Map();
    let prev = null;
    pieces.forEach((p, k) => {
      if (p.node.nodeType !== 1) return;
      const id = p.id || ('b' + (++ED.seq));
      p.node.dataset.b = id;
      ED.blocks.set(id, { src: out.slice(p.start, p.end), gap: out.slice(p.end, k + 1 < pieces.length ? pieces[k + 1].start : out.length), sig: sig(p.node), next: null });
      if (prev) ED.blocks.get(prev).next = id;
      prev = id;
    });
  }
  return text;
}
function saveMarkdown() { const t = getMarkdown(true); setDirty(false); return t; }

// ---- 編輯模式 ----
function setEditing(on) {
  ED.editing = on;
  const doc = $('doc');
  document.body.classList.toggle('editing', on);
  if (on) {
    doc.contentEditable = 'true'; doc.spellcheck = false;
    document.execCommand('defaultParagraphSeparator', false, 'p');
    const s = getSelection();
    if (!s.rangeCount || !doc.contains(s.anchorNode)) {
      // 游標放在畫面上第一個看得到的區塊開頭
      const first = Array.from(doc.querySelectorAll('h1,h2,h3,h4,h5,h6,p,li,td,pre')).find(e => e.getBoundingClientRect().bottom > 60) || doc;
      doc.focus({ preventScroll: true });
      const r = document.createRange(); r.selectNodeContents(first); r.collapse(true); s.removeAllRanges(); s.addRange(r);
    }
  } else {
    doc.removeAttribute('contenteditable'); closeLink(false);
  }
}

const exec = (c, v) => document.execCommand(c, false, v);
function selBlock() {
  const s = getSelection(); if (!s.rangeCount) return null;
  let n = s.anchorNode;
  while (n && n.id !== 'doc') {
    if (n.nodeType === 1 && /^(P|DIV|LI|H[1-6]|BLOCKQUOTE|PRE|TD|TH)$/.test(n.nodeName) && !n.classList.contains('mdb')) return n;
    n = n.parentNode;
  }
  return null;
}
function closestSel(sel) {
  const s = getSelection(); if (!s.rangeCount) return null;
  const n = s.anchorNode, el = n.nodeType === 1 ? n : n.parentElement;
  const r = el && el.closest(sel);
  return r && $('doc').contains(r) ? r : null;
}
const esc = t => t.replace(/[&<>"]/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' }[c]));
function unwrap(el) { const p = el.parentNode; while (el.firstChild) p.insertBefore(el.firstChild, el); el.remove(); }
function addCheckbox(li, checked) {
  if (!li || li.querySelector(':scope > input[type=checkbox]')) return;
  const cb = document.createElement('input');
  cb.type = 'checkbox'; cb.className = 'task-list-item-checkbox'; cb.setAttribute('contenteditable', 'false');
  if (checked) { cb.checked = true; cb.setAttribute('checked', ''); }
  li.classList.add('task-list-item'); li.insertBefore(document.createTextNode(' '), li.firstChild); li.insertBefore(cb, li.firstChild);
  setDirty(true);
}

function cmd(c) {
  const blk = selBlock(), tag = blk && blk.nodeName.toLowerCase();
  switch (c) {
    case 'p': exec('formatBlock', '<p>'); break;
    case 'h1': case 'h2': case 'h3': exec('formatBlock', tag === c ? '<p>' : '<' + c + '>'); break;
    case 'bold': case 'italic': case 'strikeThrough': exec(c); break;
    case 'code': {
      const code = closestSel('code');
      if (code && !code.closest('pre')) { const r = document.createRange(); r.selectNode(code); const s = getSelection(); s.removeAllRanges(); s.addRange(r); exec('insertText', code.textContent); }
      else { const t = getSelection().toString(); exec('insertHTML', '<code>' + esc(t || 'code') + '</code>&#8203;'); }
      break;
    }
    case 'link': showLink(); break;
    case 'ul': exec('insertUnorderedList'); break;
    case 'ol': exec('insertOrderedList'); break;
    case 'task': if (!closestSel('li')) exec('insertUnorderedList'); addCheckbox(closestSel('li'), false); break;
    case 'quote': { const q = closestSel('blockquote'); if (q) { unwrap(q); setDirty(true); } else exec('formatBlock', '<blockquote>'); break; }
    case 'pre': exec('formatBlock', closestSel('pre') ? '<p>' : '<pre>'); break;
    case 'hr': exec('insertHorizontalRule'); break;
    case 'table': exec('insertHTML', '<table><thead><tr><th>欄位 1</th><th>欄位 2</th><th>欄位 3</th></tr></thead><tbody><tr><td><br></td><td><br></td><td><br></td></tr></tbody></table><p><br></p>'); break;
  }
  refreshBar();
}

// 行首輸入 Markdown 符號加空白，自動轉成對應格式
function mdShortcut() {
  const s = getSelection(); if (!s.rangeCount || !s.isCollapsed) return;
  const blk = selBlock(); if (!blk) return;
  const r = document.createRange(); r.setStart(blk, 0); r.setEnd(s.anchorNode, s.anchorOffset);
  const pre = r.toString().replace(/ /g, ' ');
  let m, act = null;
  if (/^(P|DIV)$/.test(blk.nodeName) && !blk.closest('li')) {
    if ((m = pre.match(/^(#{1,6}) $/))) act = () => exec('formatBlock', '<h' + m[1].length + '>');
    else if (/^[-*+] $/.test(pre)) act = () => exec('insertUnorderedList');
    else if (/^1[.)] $/.test(pre)) act = () => exec('insertOrderedList');
    else if (pre === '> ') act = () => exec('formatBlock', '<blockquote>');
    else if ((m = pre.match(/^[-*]? ?\[([ xX]?)\] $/))) act = () => { exec('insertUnorderedList'); addCheckbox(closestSel('li'), /x/i.test(m[1])); };
    else if (/^(---|\*\*\*) $/.test(pre)) act = () => exec('insertHorizontalRule');
  } else if (blk.nodeName === 'LI' && (m = pre.match(/^\[([ xX]?)\] $/))) act = () => addCheckbox(blk, /x/i.test(m[1]));
  if (!act) return;
  s.removeAllRanges(); s.addRange(r); exec('delete');
  act();
}

// ---- 連結對話框 ----
let linkRange = null;
function showLink() {
  const s = getSelection(); if (!s.rangeCount) return;
  linkRange = s.getRangeAt(0).cloneRange();
  const a = closestSel('a');
  $('lk').value = a ? a.getAttribute('href') : '';
  $('lk-rm').style.display = a ? '' : 'none';
  $('linkbox').style.display = 'flex'; $('lk').focus(); $('lk').select();
}
function closeLink(restore) {
  $('linkbox').style.display = 'none';
  if (restore && linkRange) { $('doc').focus({ preventScroll: true }); const s = getSelection(); s.removeAllRanges(); s.addRange(linkRange); }
}
function applyLink(remove) {
  const url = $('lk').value.trim();
  closeLink(true);
  const a = closestSel('a');
  if (remove || !url) { if (a) { const r = document.createRange(); r.selectNodeContents(a); const s = getSelection(); s.removeAllRanges(); s.addRange(r); } exec('unlink'); return; }
  if (a) { a.setAttribute('href', url); setDirty(true); }
  else if (getSelection().isCollapsed) exec('insertHTML', '<a href="' + esc(url) + '">' + esc(url) + '</a>');
  else exec('createLink', url);
}

function refreshBar() {
  if (!ED.editing) return;
  const blk = selBlock(), tag = blk && blk.nodeName.toLowerCase();
  document.querySelectorAll('#bar button[data-c]').forEach(b => {
    const c = b.dataset.c;
    let on = false;
    if (/^(bold|italic|strikeThrough)$/.test(c)) try { on = document.queryCommandState(c) && !/^h\d$/.test(tag); } catch (e) {}
    else if (/^h\d$/.test(c)) on = tag === c;
    else if (c === 'code') on = !!closestSel('code') && !closestSel('pre');
    else if (c === 'ul') on = !!closestSel('ul') && !closestSel('li.task-list-item');
    else if (c === 'ol') on = !!closestSel('ol');
    else if (c === 'task') on = !!closestSel('li.task-list-item');
    else if (c === 'quote') on = !!closestSel('blockquote');
    else if (c === 'pre') on = !!closestSel('pre');
    else if (c === 'link') on = !!closestSel('a');
    b.classList.toggle('on', on);
  });
}

// 貼上：把剪貼簿內容先轉成 Markdown 再渲染，避免把網頁樣式整包貼進來
function onPaste(e) {
  const cd = e.clipboardData, html = cd.getData('text/html'), text = cd.getData('text/plain');
  e.preventDefault();
  if (closestSel('pre') || !html) { exec('insertText', text); return; }
  let m;
  try { m = td().turndown(html).trim(); } catch (err) { exec('insertText', text); return; }
  if (!m) return;
  exec('insertHTML', /\n/.test(m) || /^(#|[-*+] |\d+\. |>|```|\|)/.test(m) ? md.render(m) : md.renderInline(m));
}

function onKey(e) {
  if (!ED.editing || e.isComposing) return;
  const k = e.key.toLowerCase(), mod = e.metaKey && !e.ctrlKey;
  if (mod && !e.altKey) {
    if (k === 'b' && !e.shiftKey) { e.preventDefault(); return cmd('bold'); }
    if (k === 'i' && !e.shiftKey) { e.preventDefault(); return cmd('italic'); }
    if (k === 'k' && !e.shiftKey) { e.preventDefault(); return cmd('link'); }
    if (k === 'x' && e.shiftKey) { e.preventDefault(); return cmd('strikeThrough'); }
    if (k === '`') { e.preventDefault(); return cmd('code'); }
    if (k === 'u') { e.preventDefault(); return; }
  }
  if (e.target.id === 'lk') return;
  const pre = closestSel('pre');
  if (e.key === 'Enter' && pre && !e.shiftKey) {
    e.preventDefault();
    const s = getSelection(), r = document.createRange(); r.selectNodeContents(pre); r.setStart(s.anchorNode, s.anchorOffset);
    const atEnd = !r.toString().replace(/\n$/, '');
    if (atEnd && /\n$/.test(pre.textContent)) {
      // 程式碼區塊最後一行空白時再按 Enter：離開區塊
      const holder = pre.querySelector('code') || pre;
      const last = holder.lastChild;
      if (last && last.nodeType === 3) last.nodeValue = last.nodeValue.replace(/\n+$/, '');
      const p = document.createElement('p'); p.appendChild(document.createElement('br'));
      pre.after(p);
      const nr = document.createRange(); nr.setStart(p, 0); s.removeAllRanges(); s.addRange(nr);
      setDirty(true);
    } else exec('insertLineBreak');
    return;
  }
  if (e.key === 'Tab') {
    const cell = closestSel('td,th');
    if (cell) {
      e.preventDefault();
      const cells = Array.from(cell.closest('table').querySelectorAll('th,td'));
      let i = cells.indexOf(cell) + (e.shiftKey ? -1 : 1);
      if (i >= cells.length) {
        const tr = cell.closest('tr'), nr = tr.cloneNode(true);
        nr.querySelectorAll('th,td').forEach(c => { const d = document.createElement('td'); d.innerHTML = '<br>'; c.replaceWith(d); });
        (tr.closest('table').tBodies[0] || tr.parentNode).appendChild(nr);
        setDirty(true);
        i = cells.length;
      }
      const target = cell.closest('table').querySelectorAll('th,td')[Math.max(0, i)];
      const r = document.createRange(); r.selectNodeContents(target); const s = getSelection(); s.removeAllRanges(); s.addRange(r);
      return;
    }
    if (closestSel('li')) { e.preventDefault(); exec(e.shiftKey ? 'outdent' : 'indent'); return; }
    e.preventDefault(); exec('insertText', '    ');
  }
}

document.addEventListener('DOMContentLoaded', () => {
  const doc = $('doc');
  let tocT;
  doc.addEventListener('input', e => {
    if (!ED.editing) return;
    setDirty(true);
    if (e.inputType === 'insertText' && e.data === ' ') mdShortcut();
    clearTimeout(tocT); tocT = setTimeout(buildToc, 600);
  });
  doc.addEventListener('paste', e => { if (ED.editing) onPaste(e); });
  doc.addEventListener('mousedown', e => { if (ED.editing && e.target.matches && e.target.matches('input.task-list-item-checkbox')) e.preventDefault(); });
  doc.addEventListener('click', e => {
    const cb = e.target;
    if (!ED.editing || !(cb.matches && cb.matches('input.task-list-item-checkbox'))) return;
    e.preventDefault();
    const v = !cb.hasAttribute('checked');
    setTimeout(() => { cb.checked = v; v ? cb.setAttribute('checked', '') : cb.removeAttribute('checked'); setDirty(true); }, 0);
  });
  document.addEventListener('keydown', onKey, true);
  document.addEventListener('selectionchange', refreshBar);
  $('bar').addEventListener('click', e => { const b = e.target.closest('button[data-c]'); if (b) cmd(b.dataset.c); });
  $('lk-ok').onclick = () => applyLink(false);
  $('lk-rm').onclick = () => applyLink(true);
  $('lk').addEventListener('keydown', e => {
    if (e.isComposing) return;
    if (e.key === 'Enter') { e.preventDefault(); applyLink(false); }
    if (e.key === 'Escape') { e.preventDefault(); e.stopPropagation(); closeLink(true); }
  });
});
