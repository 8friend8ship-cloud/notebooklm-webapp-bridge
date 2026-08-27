(() => {
  const KEY = 'nlmDownloadClickSmoke_0_2_66';
  const sleep = (ms) => new Promise(r => setTimeout(r, ms));
  const norm = (v) => String(v || '').replace(/\s+/g, ' ').trim().toLowerCase();
  const visible = (el) => {
    if (!(el instanceof HTMLElement)) return false;
    const s = getComputedStyle(el); const r = el.getBoundingClientRect();
    return s.display !== 'none' && s.visibility !== 'hidden' && r.width > 2 && r.height > 2;
  };
  const roots = () => {
    const out=[document], seen=new Set(out);
    for(let i=0;i<out.length;i++) for(const el of out[i].querySelectorAll?.('*')||[]) if(el.shadowRoot&&!seen.has(el.shadowRoot)){seen.add(el.shadowRoot);out.push(el.shadowRoot);}
    return out;
  };
  const all = (sel) => { const out=[]; const seen=new Set(); for(const r of roots()) for(const el of r.querySelectorAll?.(sel)||[]) if(!seen.has(el)){seen.add(el);out.push(el);} return out; };
  const label = (el) => norm([el?.innerText,el?.textContent,el?.getAttribute?.('aria-label'),el?.getAttribute?.('title'),el?.getAttribute?.('data-testid')].join(' '));
  const waitFor = async (fn, timeout=10000) => { const end=Date.now()+timeout; while(Date.now()<end){try{const v=fn();if(v)return v;}catch{} await sleep(250);} return null; };
  const findMenu = () => {
    const buttons=all("button,[role='button'],a").filter(visible);
    const candidates=[];
    for(const menu of buttons){
      if(!/more_vert|more_horiz|more options|more actions|더보기|옵션|메뉴/.test(label(menu))) continue;
      let cur=menu.parentElement;
      for(let d=0;d<12&&cur;d++,cur=cur.parentElement){
        const text=norm(cur.innerText||cur.textContent||'');
        if(!text||text.length>5000) continue;
        const artifact=/오디오|audio|슬라이드|slide|보고서|report|데이터 표|data table|인포그래픽|infographic|마인드맵|mind map|플래시카드|flashcard|퀴즈|quiz/.test(text);
        const pending=/생성 중|generating|creating|만드는 중|준비 중|preparing/.test(text);
        if(artifact&&!pending){candidates.push({menu,len:text.length});break;}
      }
    }
    return candidates.sort((a,b)=>a.len-b.len)[0]?.menu||null;
  };
  const findDownload = () => {
    const overlays=all("[role='menu'],[role='listbox'],.mat-mdc-menu-panel,.mat-menu-panel,.cdk-overlay-pane").filter(visible);
    for(const o of overlays){
      const hit=[...o.querySelectorAll("[role='menuitem'],button,[role='button'],a,div,span")].filter(visible).find(el=>/(^|\s)(download|다운로드)(\s|$)/.test(label(el)));
      if(hit) return hit.closest?.("[role='menuitem'],button,[role='button'],a")||hit;
    }
    return null;
  };
  async function run(){
    try{
      const st=await chrome.storage.local.get(KEY); if(st[KEY]?.done) return;
      const menu=await waitFor(findMenu,15000); if(!menu){await chrome.storage.local.set({[KEY]:{done:false,status:'NO_ARTIFACT_MENU',at:new Date().toISOString()}});return;}
      menu.click(); await sleep(650);
      const dl=await waitFor(findDownload,8000); if(!dl){await chrome.storage.local.set({[KEY]:{done:false,status:'DOWNLOAD_ACTION_NOT_FOUND',at:new Date().toISOString()}});return;}
      dl.click();
      await chrome.storage.local.set({[KEY]:{done:true,status:'DOWNLOAD_CLICKED',at:new Date().toISOString(),url:location.href,title:document.title}});
    }catch(e){try{await chrome.storage.local.set({[KEY]:{done:false,status:'ERROR',error:String(e?.message||e),at:new Date().toISOString()}});}catch{}}
  }
  run();
})();
