(() => {
  if (globalThis.__FLOW_AGENT_BRIDGE_V020__) return;
  globalThis.__FLOW_AGENT_BRIDGE_V020__ = true;

  const TEXTBOX_SELECTORS = 'textarea,input[type="text"],input:not([type]),[contenteditable="true"],[role="textbox"]';
  const BUTTON_SELECTORS = 'button,[role="button"],a,input[type="submit"]';
  const sleep = ms => new Promise(resolve => setTimeout(resolve, ms));
  const norm = value => String(value || '').replace(/\s+/g, ' ').trim().toLowerCase();

  function roots(root = document) {
    const out = [root], queue = [root], seen = new Set(queue);
    while (queue.length) {
      const current = queue.shift();
      let all = [];
      try { all = current.querySelectorAll('*'); } catch {}
      for (const el of all) {
        if (el.shadowRoot && !seen.has(el.shadowRoot)) {
          seen.add(el.shadowRoot); out.push(el.shadowRoot); queue.push(el.shadowRoot);
        }
      }
    }
    return out;
  }

  function all(selector) {
    const out = [];
    for (const root of roots()) {
      try { out.push(...root.querySelectorAll(selector)); } catch {}
    }
    return [...new Set(out)];
  }

  function visible(el) {
    if (!el || !(el instanceof Element)) return false;
    const s = getComputedStyle(el), r = el.getBoundingClientRect();
    return s.display !== 'none' && s.visibility !== 'hidden' && Number(s.opacity) !== 0 && r.width > 18 && r.height > 18 && r.bottom >= 0 && r.right >= 0;
  }

  function describe(el) {
    return norm([
      el?.getAttribute?.('aria-label'), el?.getAttribute?.('placeholder'), el?.getAttribute?.('data-placeholder'),
      el?.getAttribute?.('title'), el?.getAttribute?.('name'), el?.id, el?.textContent, el?.value
    ].filter(Boolean).join(' '));
  }

  function promptScore(el) {
    if (!visible(el) || el.disabled || el.readOnly) return -9999;
    const text = describe(el);
    let score = 0;
    for (const w of ['prompt','describe','description','imagine','scene','video','image','create','make','what do you want','type your','enter your','프롬프트','설명','장면','영상','이미지','만들','생성','입력']) if (text.includes(w)) score += 12;
    for (const w of ['search','find','검색','댓글','comment','title','제목','name','이름']) if (text.includes(w)) score -= 20;
    if (el.tagName === 'TEXTAREA') score += 12;
    if (el.isContentEditable) score += 7;
    if (el.getAttribute('role') === 'textbox') score += 4;
    const r = el.getBoundingClientRect();
    score += Math.min(12, Math.round((r.width * r.height) / 30000));
    if (r.top > innerHeight * 0.35) score += 3;
    return score;
  }

  function findPromptBox() {
    return all(TEXTBOX_SELECTORS).map(el => ({el, score: promptScore(el)})).filter(x => x.score > -50).sort((a,b) => b.score-a.score)[0]?.el || null;
  }

  function buttonScore(el, promptBox) {
    if (!visible(el) || el.disabled || el.getAttribute('aria-disabled') === 'true') return -9999;
    const text = describe(el);
    let score = 0;
    for (const w of ['generate','create','make','submit','send','run','go','생성','만들기','실행','보내기']) if (text.includes(w)) score += 16;
    for (const w of ['cancel','close','menu','share','download','delete','settings','edit','취소','닫기','메뉴','공유','다운로드','삭제','설정']) if (text.includes(w)) score -= 30;
    if (el.tagName === 'BUTTON') score += 2;
    if (promptBox) {
      const a = promptBox.getBoundingClientRect(), b = el.getBoundingClientRect();
      const distance = Math.hypot((a.left+a.width/2)-(b.left+b.width/2), (a.top+a.height/2)-(b.top+b.height/2));
      if (distance < 220) score += 12; else if (distance < 500) score += 5;
    }
    return score;
  }

  function findGenerateButton(promptBox = findPromptBox()) {
    return all(BUTTON_SELECTORS).map(el => ({el, score: buttonScore(el, promptBox)})).filter(x => x.score > 0).sort((a,b) => b.score-a.score)[0]?.el || null;
  }

  function findWorkspaceEntry() {
    const rx = /(create with google flow|new project|create project|start creating|새 프로젝트|프로젝트 만들기|만들기 시작)/i;
    return all(BUTTON_SELECTORS).filter(visible).map(el => ({el, text: describe(el)})).find(x => rx.test(x.text))?.el || null;
  }

  function setNativeValue(el, value) {
    const proto = el.tagName === 'TEXTAREA' ? HTMLTextAreaElement.prototype : HTMLInputElement.prototype;
    const setter = Object.getOwnPropertyDescriptor(proto, 'value')?.set;
    if (setter) setter.call(el, value); else el.value = value;
  }

  function setPrompt(text) {
    const el = findPromptBox();
    if (!el) throw new Error('FLOW_PROMPT_NOT_FOUND');
    el.focus();
    if (el instanceof HTMLTextAreaElement || el instanceof HTMLInputElement) setNativeValue(el, text);
    else if (el.isContentEditable || el.getAttribute('role') === 'textbox') {
      const sel = window.getSelection(), range = document.createRange();
      range.selectNodeContents(el); sel.removeAllRanges(); sel.addRange(range);
      const inserted = document.execCommand?.('insertText', false, text);
      if (!inserted) el.textContent = text;
      sel.removeAllRanges();
    } else el.textContent = text;
    for (const type of ['input','change','keyup']) el.dispatchEvent(new Event(type,{bubbles:true,composed:true}));
    return {ok:true, element:describe(el).slice(0,160)};
  }

  function clickGenerate() {
    const box = findPromptBox(), button = findGenerateButton(box);
    if (!button) throw new Error('FLOW_GENERATE_NOT_FOUND');
    button.focus(); button.click();
    return {ok:true, button:describe(button).slice(0,160)};
  }

  async function ensureWorkspace(timeoutMs = 20000) {
    const deadline = Date.now() + timeoutMs;
    let entryClicked = false;
    while (Date.now() < deadline) {
      const box = findPromptBox();
      if (box) return {ok:true, promptFound:true, generateFound:Boolean(findGenerateButton(box)), entryClicked};
      const entry = findWorkspaceEntry();
      if (entry) { entry.click(); entryClicked = true; await sleep(1800); continue; }
      await sleep(600);
    }
    return {ok:false, promptFound:false, generateFound:false, entryClicked, error:'FLOW_WORKSPACE_NOT_READY'};
  }

  function inspect() {
    const box = findPromptBox();
    return {ok:true,url:location.href,title:document.title,promptFound:Boolean(box),generateFound:Boolean(findGenerateButton(box)),loginRequired:/accounts\.google\.com/i.test(location.href)};
  }

  chrome.runtime.onMessage.addListener((message, _sender, sendResponse) => {
    (async () => {
      try {
        switch (message?.type) {
          case 'PING': sendResponse(inspect()); break;
          case 'ENSURE_WORKSPACE': sendResponse(await ensureWorkspace(Number(message.timeoutMs || 20000))); break;
          case 'FILL_PROMPT': sendResponse(setPrompt(String(message.prompt || ''))); break;
          case 'CLICK_GENERATE': sendResponse(clickGenerate()); break;
          case 'FILL_AND_GENERATE': {
            const ready = await ensureWorkspace(); if (!ready.ok) throw new Error(ready.error);
            const filled = setPrompt(String(message.prompt || '')); await sleep(550); const clicked = clickGenerate();
            sendResponse({ok:true,filled,clicked}); break;
          }
          default: sendResponse({ok:false,error:'UNKNOWN_FLOW_COMMAND'});
        }
      } catch (error) { sendResponse({ok:false,error:error?.message || String(error)}); }
    })();
    return true;
  });
})();
