import fs from 'node:fs';
const p='notebooklm-webapp-bridge-source-v0.2.0/frontend/app.js';
const s=fs.readFileSync(p,'utf8');
const must=[
  'auto_select:false',
  'initGoogle(true);',
  'initGoogle(false);',
  '로그인 버튼을 눌러 재인증하세요'
];
for(const x of must){ if(!s.includes(x)) throw new Error('MISSING:'+x); }
if(s.includes('google.accounts.id.prompt(')) throw new Error('AUTO_PROMPT_STILL_PRESENT');
if(/initGoogle\([^)]*,\s*true\)/.test(s)) throw new Error('PROMPT_FLAG_STILL_PRESENT');
console.log('FRONTEND_GOOGLE_CONSENT_LOOP_STATIC_PASS');
