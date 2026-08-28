const fs = require('fs');
const vm = require('vm');
const assert = require('assert');

const source = fs.readFileSync('apps-script/CentralDailyWorkflowGovernorV2.gs', 'utf8');
const ctx = {};
vm.createContext(ctx);
vm.runInContext(source, ctx, { filename: 'CentralDailyWorkflowGovernorV2.gs' });

assert.strictEqual(typeof ctx.decideCentralPromotionV2_, 'function');

const apiFree = ctx.decideCentralPromotionV2_('PASS', 'API_QA_DISABLED_POLICY');
assert.deepStrictEqual(JSON.parse(JSON.stringify(apiFree)), {
  approved: true,
  approvalMode: 'API_FREE_BASELINE',
  finalStatus: 'PASS_APPROVED_FOR_PROMOTION_API_FREE'
});

const dual = ctx.decideCentralPromotionV2_('PASS', 'PASS_BOTH_MODELS');
assert.deepStrictEqual(JSON.parse(JSON.stringify(dual)), {
  approved: true,
  approvalMode: 'DUAL_QA',
  finalStatus: 'PASS_APPROVED_FOR_PROMOTION_DUAL_QA'
});

const baselineFail = ctx.decideCentralPromotionV2_('NEEDS_FIX', 'API_QA_DISABLED_POLICY');
assert.strictEqual(baselineFail.approved, false);
assert.strictEqual(baselineFail.finalStatus, 'NEEDS_FIX_BASELINE');

const explicitlyEnabledButBroken = ctx.decideCentralPromotionV2_('PASS', 'BLOCKED_ACCESS_MISSING_AI_QA_CONFIG');
assert.strictEqual(explicitlyEnabledButBroken.approved, false);
assert.strictEqual(explicitlyEnabledButBroken.finalStatus, 'BLOCKED_ACCESS_MISSING_AI_QA_CONFIG');

console.log('central governor policy regression: PASS');
