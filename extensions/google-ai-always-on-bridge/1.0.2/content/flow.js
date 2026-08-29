(() => {
  if (globalThis.__GOOGLE_AI_ALWAYS_ON_FLOW_V102__) return;
  globalThis.__GOOGLE_AI_ALWAYS_ON_FLOW_V102__ = true;

  const VERSION = '1.0.2';
  const TEXTBOX_SELECTORS = [
    'textarea',
    'input[type="text"]',
    'input:not([type])',
    '[contenteditable="true"]',
    '[role="textbox"]'
  ].join(',');
  const BUTTON_SELECTORS = ['button','[role="button"]','input[type="submit"]'].join(',');
  const sleep = ms => new Promise(resolve => setTimeout(resolve, ms));
  const normalize = value => String(value || '').replace(/\s+/g, ' ').trim().toLowerCase();

  function describeElement(el) {
    return normalize([
      el?.getAttribute?.('aria-label'),
      el?.getAttribute?.('placeholder'),
      el?.getAttribute?.('data-placeholder'),
      el?.getAttribute?.('title'),
      el?.getAttribute?.('name'),
      el?.id,
      el?.textContent,
      el?.value
    ].filter(Boolean).join(' '));
  }

  function isVisible(el) {
    if (!el || !(el instanceof Element)) return false;
    const style = getComputedStyle(el);
    if (style.display === 'none' || style.visibility === 'hidden' || Number(style.opacity) === 0) return false;
    const rect = el.getBoundingClientRect();
    return rect.width > 18 && rect.height > 18 && rect.bottom >= 0 && rect.right >= 0;
  }

  function walkRoots(root = document) {
    const roots = [root];
    const queue = [root];
    const seen = new Set(queue);
    while (queue.length) {
      const current = queue.shift();
      const all = current.querySelectorAll ? current.querySelectorAll('*') : [];
      for (const el of all) {
        if (el.shadowRoot && !seen.has(el.shadowRoot)) {
          roots.push(el.shadowRoot);
          queue.push(el.shadowRoot);
          seen.add(el.shadowRoot);
        }
      }
    }
    return roots;
  }

  function allMatches(selector) {
    const out = [];
    for (const root of walkRoots()) {
      try { out.push(...root.querySelectorAll(selector)); } catch (_) {}
    }
    return [...new Set(out)];
  }

  function textboxScore(el) {
    if (!isVisible(el) || el.disabled || el.readOnly) return -9999;
    const text = describeElement(el);
    let score = 0;
    const positive = [
      'prompt','describe','description','imagine','scene','video','image',
      'create','make','what do you want','type your','enter your',
      '프롬프트','설명','장면','영상','이미지','만들','생성','입력'
    ];
    const negative = ['search','find','검색','댓글','comment','title','제목','name','이름'];
    for (const word of positive) if (text.includes(word)) score += 12;
    for (const word of negative) if (text.includes(word)) score -= 20;
    if (el.tagName === 'TEXTAREA') score += 12;
    if (el.isContentEditable) score += 7;
    if (el.getAttribute('role') === 'textbox') score += 4;
    const rect = el.getBoundingClientRect();
    score += Math.min(12, Math.round((rect.width * rect.height) / 30000));
    if (rect.top > innerHeight * 0.45) score += 3;
    return score;
  }

  function findPromptBox() {
    return allMatches(TEXTBOX_SELECTORS)
      .map(el => ({ el, score: textboxScore(el) }))
      .filter(item => item.score > -50)
      .sort((a, b) => b.score - a.score)[0]?.el || null;
  }

  function buttonScore(el, promptBox) {
    if (!isVisible(el) || el.disabled || el.getAttribute('aria-disabled') === 'true') return -9999;
    const text = describeElement(el);
    let score = 0;
    const strong = ['generate','create','make','submit','send','run','go','생성','만들기','실행','보내기'];
    const weak = ['arrow_upward','send','play_arrow'];
    const negative = ['cancel','close','menu','share','download','delete','settings','edit','취소','닫기','메뉴','공유','다운로드','삭제','설정'];
    for (const word of strong) if (text.includes(word)) score += 16;
    for (const word of weak) if (text.includes(word)) score += 5;
    for (const word of negative) if (text.includes(word)) score -= 30;
    if (el.tagName === 'BUTTON') score += 2;
    if (promptBox) {
      const a = promptBox.getBoundingClientRect();
      const b = el.getBoundingClientRect();
      const dx = Math.abs((a.left + a.width / 2) - (b.left + b.width / 2));
      const dy = Math.abs((a.top + a.height / 2) - (b.top + b.height / 2));
      const distance = Math.sqrt(dx * dx + dy * dy);
      if (distance < 220) score += 12;
      else if (distance < 500) score += 5;
    }
    return score;
  }

  function findGenerateButton(promptBox = findPromptBox()) {
    return allMatches(BUTTON_SELECTORS)
      .map(el => ({ el, score: buttonScore(el, promptBox) }))
      .filter(item => item.score > 0)
      .sort((a, b) => b.score - a.score)[0]?.el || null;
  }

  function findExactButton(patterns) {
    return allMatches(BUTTON_SELECTORS).find(el => {
      if (!isVisible(el) || el.disabled || el.getAttribute('aria-disabled') === 'true') return false;
      const text = normalize(el.textContent || el.value || el.getAttribute('aria-label') || '');
      return patterns.some(rx => rx.test(text));
    }) || null;
  }

  async function ensureWorkspace(timeoutMs = 45000) {
    const started = Date.now();
    const history = [];
    while (Date.now() - started < timeoutMs) {
      if (location.href.includes('accounts.google.com')) {
        return { ok:false, status:'NEEDS_USER', error:'Google login required', history };
      }
      const prompt = findPromptBox();
      if (prompt) return { ok:true, status:'CONNECTED', promptFound:true, history };

      const primary = findExactButton([/^create with google flow$/i,/^create with flow$/i,/^start creating$/i,/^enter flow$/i,/^try flow$/i,/^open flow$/i]);
      if (primary) {
        history.push({step:'FLOW_PRIMARY_CTA', text:describeElement(primary).slice(0,120)});
        primary.click();
        await sleep(1800);
        continue;
      }
      const newProject = findExactButton([/^new project$/i,/^새\s*프로젝트$/i]);
      if (newProject) {
        history.push({step:'FLOW_NEW_PROJECT', text:describeElement(newProject).slice(0,120)});
        newProject.click();
        await sleep(1800);
        continue;
      }
      await sleep(700);
    }
    return { ok:false, status:'NEEDS_USER', error:'Flow workspace not reached', history };
  }

  function setNativeValue(el, value) {
    const proto = el.tagName === 'TEXTAREA' ? HTMLTextAreaElement.prototype : HTMLInputElement.prototype;
    const descriptor = Object.getOwnPropertyDescriptor(proto, 'value');
    if (descriptor?.set) descriptor.set.call(el, value);
    else el.value = value;
  }

  function setPrompt(text) {
    const el = findPromptBox();
    if (!el) throw new Error('Flow prompt box not found');
    el.focus();
    if (el instanceof HTMLTextAreaElement || el instanceof HTMLInputElement) {
      setNativeValue(el, text);
    } else if (el.isContentEditable || el.getAttribute('role') === 'textbox') {
      const selection = window.getSelection();
      const range = document.createRange();
      range.selectNodeContents(el);
      selection.removeAllRanges();
      selection.addRange(range);
      const inserted = document.execCommand?.('insertText', false, text);
      if (!inserted) el.textContent = text;
      selection.removeAllRanges();
    } else {
      el.textContent = text;
    }
    for (const type of ['input','change','keyup']) el.dispatchEvent(new Event(type,{bubbles:true,composed:true}));
    return { ok:true, element:describeElement(el).slice(0,120) };
  }

  function clickGenerate() {
    const promptBox = findPromptBox();
    const button = findGenerateButton(promptBox);
    if (!button) throw new Error('Flow generate button not found');
    button.focus();
    button.click();
    return { ok:true, button:describeElement(button).slice(0,120) };
  }

  function getPrompt(task) {
    return String(task?.prompt || task?.PROMPT || task?.promptText || task?.prompt_text || task?.scenePrompt || task?.SCENE_PROMPT || task?.input || task?.INPUT || task?.text || '').trim();
  }

  function isProbe(task) {
    const action = normalize(task?.action || task?.taskType || task?.type || '');
    return !action || /(probe|ping|health|connect|connection|inspect|readonly|read_only|check|verify)/i.test(action);
  }

  function generationApproved(task) {
    return task?.allowGenerate === true || task?.creditApproved === true || task?.generationApproved === true || task?.approval === 'APPROVED' || task?.approvalStatus === 'APPROVED';
  }

  async function run(task) {
    if (location.href.includes('accounts.google.com')) return {status:'NEEDS_USER',error:'Google login required',version:VERSION};
    const workspace = await ensureWorkspace();
    if (!workspace.ok) return {...workspace, version:VERSION, generateClicked:false, creditSpend:false};

    const promptBox = findPromptBox();
    const generateButton = findGenerateButton(promptBox);
    const base = {
      version: VERSION,
      url: location.href,
      promptFound: Boolean(promptBox),
      generateFound: Boolean(generateButton),
      history: workspace.history,
      generateClicked: false,
      creditSpend: false
    };

    if (isProbe(task)) return { ...base, status:'CONNECTED', ok:Boolean(promptBox) };
    if (!generationApproved(task)) return { ...base, status:'BLOCKED_CREDIT_GATE', ok:false, error:'Flow generation requires explicit credit approval' };

    const prompt = getPrompt(task);
    if (!prompt) return { ...base, status:'FAILED', ok:false, error:'Flow task prompt missing' };
    const filled = setPrompt(prompt);
    await sleep(550);
    const clicked = clickGenerate();
    return { ...base, status:'SUBMITTED', ok:true, filled, clicked, generateClicked:true, creditSpend:true };
  }

  chrome.runtime.onMessage.addListener((msg,_sender,sendResponse) => {
    if (msg?.type !== 'RUN_BRIDGE_TASK') return;
    run(msg.task).then(sendResponse).catch(error => sendResponse({
      status:'FAILED', ok:false, error:error?.message || String(error), version:VERSION,
      generateClicked:false, creditSpend:false
    }));
    return true;
  });
})();
