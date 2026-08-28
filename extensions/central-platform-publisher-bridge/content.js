(()=>{
  const PLATFORM=(()=>{
    const h=location.hostname;
    if(h.includes('blogger.com'))return 'BLOGGER';
    if(h==='studio.youtube.com'||h.endsWith('youtube.com'))return 'YOUTUBE';
    if(h.endsWith('instagram.com'))return 'INSTAGRAM';
    if(h.endsWith('tiktok.com'))return 'TIKTOK';
    if(h==='blog.naver.com')return 'NAVER_BLOG';
    if(h==='cafe.naver.com')return 'NAVER_CAFE';
    if(h==='clip.naver.com')return 'NAVER_CLIP';
    if(h.endsWith('pinterest.com'))return 'PINTEREST';
    return 'UNKNOWN';
  })();
  const SELECTORS={
    BLOGGER:['textarea','input[type="text"]','[contenteditable="true"]'],
    YOUTUBE:['textarea','input[type="text"]','ytcp-social-suggestion-input input','[contenteditable="true"]'],
    INSTAGRAM:['textarea','input[type="text"]','[contenteditable="true"]'],
    TIKTOK:['textarea','input[type="text"]','[contenteditable="true"]'],
    NAVER_BLOG:['textarea','input[type="text"]','[contenteditable="true"]'],
    NAVER_CAFE:['textarea','input[type="text"]','[contenteditable="true"]'],
    NAVER_CLIP:['textarea','input[type="text"]','[contenteditable="true"]'],
    PINTEREST:['textarea','input[type="text"]','[contenteditable="true"]']
  };
  function candidates(){const out=[];for(const s of (SELECTORS[PLATFORM]||[])){for(const el of document.querySelectorAll(s)){const r=el.getBoundingClientRect();if(r.width>0&&r.height>0&&!el.disabled)out.push({selector:s,el})}}return out}
  function probe(){const c=candidates();return {ok:true,platform:PLATFORM,url:location.href,title:document.title,loginRequired:/login|signin|로그인/i.test(document.body?.innerText?.slice(0,4000)||''),candidateCount:c.length,candidates:c.slice(0,12).map(x=>({selector:x.selector,tag:x.el.tagName,type:x.el.getAttribute('type')||'',aria:x.el.getAttribute('aria-label')||''}))}}
  function setValue(el,value){el.focus();if(el.isContentEditable){el.textContent=value;el.dispatchEvent(new InputEvent('input',{bubbles:true,inputType:'insertText',data:value}))}else{const proto=el.tagName==='TEXTAREA'?HTMLTextAreaElement.prototype:HTMLInputElement.prototype;const setter=Object.getOwnPropertyDescriptor(proto,'value')?.set;if(setter)setter.call(el,value);else el.value=value;el.dispatchEvent(new Event('input',{bubbles:true}));el.dispatchEvent(new Event('change',{bubbles:true}))}}
  chrome.runtime.onMessage.addListener((msg,_sender,sendResponse)=>{
    try{
      if(msg?.type==='CENTRAL_BRIDGE_PROBE')return sendResponse(probe());
      if(msg?.type==='CENTRAL_BRIDGE_FILL_DRAFT'){
        const c=candidates();if(!c.length)return sendResponse({ok:false,platform:PLATFORM,error:'NO_EDITABLE_TARGET'});
        const text=String(msg.text||'');setValue(c[0].el,text);return sendResponse({ok:true,platform:PLATFORM,filled:true,readback:(c[0].el.isContentEditable?c[0].el.textContent:c[0].el.value)||''});
      }
      if(msg?.type==='CENTRAL_BRIDGE_CLEAR_DRAFT'){
        const c=candidates();if(!c.length)return sendResponse({ok:false,error:'NO_EDITABLE_TARGET'});setValue(c[0].el,'');return sendResponse({ok:true,cleared:true});
      }
      if(msg?.type==='CENTRAL_BRIDGE_PUBLISH')return sendResponse({ok:false,error:'PUBLIC_PUBLISH_FAIL_CLOSED',detail:'Publishing is disabled until platform-specific selector and approval gates pass.'});
    }catch(e){return sendResponse({ok:false,error:String(e&&e.message||e)})}
    return false;
  });
})();
