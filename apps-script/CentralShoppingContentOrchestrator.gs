var CENTRAL_SHOPPING_CONTENT_ORCH_VERSION = 'CENTRAL_SHOPPING_CONTENT_ORCH_V1_20260829';
var CENTRAL_SHOPPING_MASTER_ID = '1C_CznU1Uo7dk-gKay3-oH8wFxutsGMlz27RSrbdVQwI';

var CENTRAL_SHOPPING_APP_PROFILES = {
  APP_CONTENT_OS: ['ARTICLE_RELATED_PRODUCT','CONTENT_TOOL','REFERENCE_PRODUCT','CREATOR_GEAR','AFFILIATE_LINK_OPPORTUNITY','VIDEO_PPL_OPPORTUNITY'],
  APP_ANALYZER: ['TARGET_PHYSICAL_PRODUCT','CONTENT_RELATED_PRODUCT','AFFILIATE_LINK_OPPORTUNITY'],
  APP_KFOOD: ['INGREDIENT','PACKAGED_FOOD','KITCHEN_TOOL','STORAGE','SERVING_ITEM'],
  APP_INTERIOR: ['MATERIAL','FURNITURE','DECOR','APPLIANCE','LIFESTYLE_GOOD','TOOL','INSTALLATION_PART'],
  APP_TRAVEL: ['TRAVEL_GEAR','LOCAL_GOOD','SIM_CONNECTIVITY','TRANSPORT_ITEM','TICKET','PASS','RESERVATION'],
  APP_VTUBE_1011B: ['COSTUME','PROP','CAMERA_LIGHTING','AUDIO_GEAR','BACKDROP','STREAM_ACCESSORY','VIDEO_PPL_OPPORTUNITY'],
  APP_VTUBE: ['COSTUME','PROP','CAMERA_LIGHTING','AUDIO_GEAR','BACKDROP','STREAM_ACCESSORY','VIDEO_PPL_OPPORTUNITY'],
  APP_SHORTS: ['COSTUME','PROP','SET_DECOR','LIGHTING','CAMERA_AUDIO_ACCESSORY','SHORTS_PPL_OPPORTUNITY'],
  APP_ANIMATION: ['PROP','SET_ITEM','REFERENCE_PRODUCT','VIDEO_PPL_OPPORTUNITY'],
  APP_DRYWRITE: ['REFERENCE_BOOK','PHYSICAL_REFERENCE','PROP','SET_ITEM','ARTICLE_RELATED_PRODUCT'],
  APP_WRITE: ['ARTICLE_RELATED_PRODUCT','REFERENCE_PRODUCT','AFFILIATE_LINK_OPPORTUNITY'],
  APP_BOTS: ['CLOTHING','COSTUME','ACCESSORY','PROP','MAKEUP','CHARACTER_ITEM','VOICE_STREAM_GEAR'],
  APP_BOTS_FRONTEND: ['CLOTHING','COSTUME','ACCESSORY','PROP','MAKEUP','CHARACTER_ITEM','VOICE_STREAM_GEAR'],
  APP_BIBLE365: ['BOOK','STUDY_MATERIAL','PRINT_GIFT','TEACHING_PROP'],
  APP_LECTURE: ['BOOK','COURSE_MATERIAL','TEACHING_PROP','PRESENTATION_EQUIPMENT'],
  APP_PUBLISHER_CORE: ['PUBLISH_EXISTING_VERIFIED_SHOPPING_PACKAGE_ONLY']
};

function evaluateFrontShoppingNeedV1(input) {
  input = input || {};
  var appId = String(input.appId || '').trim();
  var requestText = [input.goal, input.query, input.content, input.requirement, input.outputMode].filter(Boolean).join(' ').toLowerCase();
  var profile = CENTRAL_SHOPPING_APP_PROFILES[appId] || [];
  if (!appId) return {ok:false,status:'UNKNOWN',reason:'APP_ID_REQUIRED',version:CENTRAL_SHOPPING_CONTENT_ORCH_VERSION};
  if (!profile.length) return {ok:true,appId:appId,status:'NONE',reason:'NO_REGISTERED_SHOPPING_PROFILE',categories:[],version:CENTRAL_SHOPPING_CONTENT_ORCH_VERSION};

  var explicit = input.shoppingRequired === true || input.shoppingOptional === true || /구매|쇼핑|가격|가성비|재료|자재|소품|의상|장비|추천|제품|상품|입장권|예약|affiliate|ppl|product|buy|price/.test(requestText);
  var contentOpportunity = /글|기사|콘텐츠|영상|쇼츠|릴스|블로그|video|short|reel|article|content/.test(requestText);
  var status = input.shoppingRequired === true ? 'REQUIRED' : (explicit || contentOpportunity ? 'OPTIONAL' : 'NONE');

  if ((appId === 'APP_TRAVEL') && /호텔|식당|restaurant|hotel|venue/.test(requestText)) {
    return {ok:true,appId:appId,status:status,route:'TRAVEL_LIVE_BOOKING_LANE',categories:['TICKET','PASS','RESERVATION'],reason:'TRAVEL_PLACE_REVIEW_ISOLATED_FROM_BRG_032',version:CENTRAL_SHOPPING_CONTENT_ORCH_VERSION};
  }

  return {
    ok:true,
    appId:appId,
    status:status,
    categories:profile,
    route:status === 'NONE' ? 'NORMAL_APP_PIPELINE' : 'SEED_FIRST→BRG_032_IF_NEEDED→LIVE_OFFER→CONTENT_SLOT_QA',
    contentOpportunity:contentOpportunity,
    reason:status === 'NONE' ? 'NO_USEFUL_COMMERCE_NEED_DETECTED' : 'REGISTERED_APP_PROFILE_AND_REQUEST_CONTEXT_MATCH',
    version:CENTRAL_SHOPPING_CONTENT_ORCH_VERSION
  };
}

function buildShoppingContentPackageV1(input) {
  input = input || {};
  var need = evaluateFrontShoppingNeedV1(input);
  if (!need.ok || need.status === 'NONE') return {ok:need.ok,status:need.status,need:need,package:null,version:CENTRAL_SHOPPING_CONTENT_ORCH_VERSION};

  var offer = input.offer || {};
  var evidence = input.evidence || {};
  var priceVerified = offer.priceVerified === true && isFinite(Number(offer.totalCost));
  var availabilityVerified = offer.availabilityVerified === true && String(offer.availability || '').toUpperCase() !== 'UNKNOWN';
  var productIdentityVerified = evidence.productIdentityVerified === true;
  var repeatedSignalQualified = evidence.repeatedSignalQualified === true || evidence.officialSourceVerified === true;
  var recommendationReady = priceVerified && availabilityVerified && productIdentityVerified && repeatedSignalQualified;
  var commercialRelationship = input.affiliate === true || input.sponsored === true || input.freeProduct === true || input.paidPlacement === true;
  var outputMode = String(input.outputMode || 'ARTICLE').toUpperCase();

  var packageResult = {
    packageId: String(input.packageId || ('SHOP_' + new Date().getTime())),
    appId: need.appId,
    taskId: input.taskId || '',
    outputMode: outputMode,
    shoppingNeedStatus: need.status,
    recommendationReady: recommendationReady,
    recommendationReason: recommendationReady ? String(input.recommendationReason || 'Verified task fit, price, availability and qualified evidence.') : 'HOLD_UNTIL_VERIFIED_PRICE_AVAILABILITY_IDENTITY_AND_EVIDENCE',
    alternatives: Array.isArray(input.alternatives) ? input.alternatives.slice(0,2) : [],
    offer: offer,
    evidence: evidence,
    disclosure: {
      required: commercialRelationship,
      affiliate: input.affiliate === true,
      sponsored: input.sponsored === true,
      freeProduct: input.freeProduct === true,
      paidPlacement: input.paidPlacement === true,
      state: commercialRelationship ? 'REQUIRED_BEFORE_PUBLISH' : 'NOT_REQUIRED_BY_RELATIONSHIP_INPUT'
    },
    articleSlot: outputMode.indexOf('ARTICLE') >= 0 || outputMode.indexOf('BLOG') >= 0 ? {
      flow:['context_or_problem','useful_explanation','why_item_needed','verified_reason','two_alternatives','price_delivery_timestamp','optional_link','disclosure']
    } : null,
    videoPplSlot: /VIDEO|SHORT|REEL|VTUBE/.test(outputMode) ? {
      sceneId: input.sceneId || '',
      placementReason: input.placementReason || '',
      visibilityWindowSec: Math.max(0, Number(input.visibilityWindowSec || 0)),
      dialogueOptional: input.dialogueOptional !== false,
      ctaOptional: input.ctaOptional !== false,
      fatigueCap: input.fatigueCap || 'ONE_NATURAL_SLOT_PER_SEGMENT',
      removeIfContentQualityDrops: true,
      disclosureRequired: commercialRelationship,
      offerVerifiedAt: offer.verifiedAt || ''
    } : null,
    publish: {
      route:'APP_T1_T2→PLATFORM_DRAFT→PUBLISHER_CORE',
      publicPublishHumanGate:true,
      failClosedOrganicDraft:!recommendationReady
    },
    learning: {
      promoteOnlyAfter:['CONTENT_QUALITY_PASS','OFFER_VALID','DISCLOSURE_PASS_IF_REQUIRED','TASK_FIT_PASS','RUNTIME_READBACK_X2'],
      affiliateClickAloneNeverSuccess:true
    },
    version:CENTRAL_SHOPPING_CONTENT_ORCH_VERSION
  };

  return {ok:true,status:recommendationReady ? 'DRAFT_READY' : 'COMMERCE_HOLD_ORGANIC_DRAFT_OK',need:need,package:packageResult,version:CENTRAL_SHOPPING_CONTENT_ORCH_VERSION};
}

function runCentralShoppingContentOrchestratorHourly() {
  var lock = LockService.getScriptLock();
  if (!lock.tryLock(1000)) return {ok:true,skipped:true,reason:'LOCK_BUSY',version:CENTRAL_SHOPPING_CONTENT_ORCH_VERSION};
  try {
    var ss = SpreadsheetApp.openById(CENTRAL_SHOPPING_MASTER_ID);
    var tz = ss.getSpreadsheetTimeZone() || 'Asia/Seoul';
    var bucket = Utilities.formatDate(new Date(), tz, 'yyyyMMddHH');
    var props = PropertiesService.getScriptProperties();
    var last = props.getProperty('CENTRAL_SHOPPING_CONTENT_ORCH_LAST_BUCKET');
    if (last === bucket) return {ok:true,skipped:true,reason:'ALREADY_RAN_BUCKET',bucket:bucket,version:CENTRAL_SHOPPING_CONTENT_ORCH_VERSION};

    var requiredSheets = ['18_AGENT_INSTRUCTION','24_CHROME_BRIDGE_REGISTRY','35_INTERNAL_SEED_REGISTRY','36_AUTOMATION_TRIGGER_REGISTRY','39_CHANNEL_PUBLISH_MAP','56_FRONTAPP_WORKFLOW_MAP','61_BACKEND_FUNCTION_CONTRACT','63_EVOLUTION_CHANGELOG','75_ORCHESTRA_WORKFLOW_MAP','77_TEMPLATE_EVOLUTION_FACTORY','87_AD_MONETIZATION_POLICY'];
    var missing = requiredSheets.filter(function(name){ return !ss.getSheetByName(name); });
    if (missing.length) {
      writeCentralShoppingAudit_(ss,'CENTRAL_SHOPPING_CONTENT_ORCH','MISSING_SHEETS','BLOCKED','MEDIUM','Missing: '+missing.join(','));
      return {ok:false,missingSheets:missing,version:CENTRAL_SHOPPING_CONTENT_ORCH_VERSION};
    }

    var wf = ss.getSheetByName('56_FRONTAPP_WORKFLOW_MAP').getDataRange().getDisplayValues();
    var header = wf[0] || [];
    var appIdx = header.indexOf('APP_ID');
    var routeIdx = header.indexOf('CENTRAL_ROUTE');
    var mediaIdx = header.indexOf('MEDIA_RULE');
    var activeApps = [];
    var gaps = [];
    for (var r = 1; r < wf.length; r++) {
      var appId = appIdx >= 0 ? String(wf[r][appIdx] || '') : '';
      if (!appId || !CENTRAL_SHOPPING_APP_PROFILES[appId]) continue;
      activeApps.push(appId);
      var combined = [routeIdx >= 0 ? wf[r][routeIdx] : '', mediaIdx >= 0 ? wf[r][mediaIdx] : ''].join(' ');
      if (!/SHOP|BRG_032|PPL|COMMERCE/i.test(combined)) gaps.push(appId);
    }

    props.setProperty('CENTRAL_SHOPPING_CONTENT_ORCH_LAST_BUCKET', bucket);
    var result = {ok:true,bucket:bucket,registeredApps:Object.keys(CENTRAL_SHOPPING_APP_PROFILES).length,mappedApps:activeApps.length,workflowGaps:gaps,externalCrawlStarted:false,publicPublishStarted:false,version:CENTRAL_SHOPPING_CONTENT_ORCH_VERSION};
    writeCentralShoppingAudit_(ss,'CENTRAL_SHOPPING_CONTENT_ORCH','LOGICAL_HOURLY_CROSSCHECK',gaps.length ? 'GAP_FOUND' : 'PASS',gaps.length ? 'LOW' : 'LOW',JSON.stringify(result));
    return result;
  } finally {
    lock.releaseLock();
  }
}

function runCentralShoppingContentDailyLearningV1(input) {
  input = input || {};
  var result = buildShoppingContentPackageV1(input);
  return {
    ok:true,
    packageStatus:result.status,
    writebackTargets:['35_INTERNAL_SEED_REGISTRY','63_EVOLUTION_CHANGELOG','75_ORCHESTRA_WORKFLOW_MAP','77_TEMPLATE_EVOLUTION_FACTORY'],
    promotionGate:['CONTENT_QUALITY_PASS','OFFER_VALID','DISCLOSURE_PASS_IF_REQUIRED','TASK_FIT_PASS','RUNTIME_READBACK_X2'],
    noNewPhysicalTrigger:true,
    version:CENTRAL_SHOPPING_CONTENT_ORCH_VERSION
  };
}

function writeCentralShoppingAudit_(ss, targetId, action, result, risk, notes) {
  var sh = ss.getSheetByName('08_AUDIT_LOG');
  if (!sh) return;
  var now = new Date();
  var tz = ss.getSpreadsheetTimeZone() || 'Asia/Seoul';
  var stamp = Utilities.formatDate(now, tz, 'yyyy-MM-dd HH:mm:ss');
  var auditId = 'AUDIT_SHOP_' + Utilities.formatDate(now, tz, 'yyyyMMdd_HHmmss');
  sh.appendRow([auditId, stamp, 'CENTRAL', 'WORKFLOW', targetId, action, result, risk || 'LOW', String(notes || '').slice(0,5000)]);
}
