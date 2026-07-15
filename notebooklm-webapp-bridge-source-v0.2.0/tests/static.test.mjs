import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";
const read=(path)=>readFile(new URL(`../${path}`,import.meta.url),"utf8");

test("extension supports external frontend bridge",async()=>{
  const manifest=JSON.parse(await read("extension/manifest.json"));
  assert.equal(manifest.manifest_version,3);
  assert.ok(manifest.externally_connectable.matches.includes("https://*.vercel.app/*"));
  assert.ok(manifest.permissions.includes("identity.email"));
  assert.ok(manifest.host_permissions.includes("https://notebooklm.google.com/*"));
});
test("background validates and receives external messages",async()=>{
  const source=await read("extension/background.js");
  assert.match(source,/onMessageExternal/);
  assert.match(source,/claimTask/);
  assert.match(source,/chromeProfileEmail/);
  assert.match(source,/frontendOrigin/);
  assert.equal(/\beval\s*\(/.test(source),false);
});
test("frontend includes Google login and extension dispatch",async()=>{
  const source=await read("frontend/app.js");
  assert.match(source,/google\.accounts\.id/);
  assert.match(source,/chrome\.runtime\.sendMessage/);
  assert.match(source,/RUN_TASK/);
});
test("Apps Script implements auth queue drive and writer callback",async()=>{
  const source=await read("apps-script/Code.gs");
  for(const token of ["tokeninfo","claimTask_","completeTask_","DriveApp","enqueueFromWriter_","notifyWriter_"]) assert.ok(source.includes(token),token);
});
test("no committed credentials",async()=>{
  const files=["frontend/config.js","extension/background.js","apps-script/Code.gs"];
  for(const file of files){const source=await read(file);assert.equal(/AIza[0-9A-Za-z_-]{20,}/.test(source),false,file);}
});
