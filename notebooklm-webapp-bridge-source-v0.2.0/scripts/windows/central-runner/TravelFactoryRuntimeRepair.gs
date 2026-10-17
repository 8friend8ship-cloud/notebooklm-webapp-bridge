/**
 * APP_TRAVEL runtime repair diagnostics. Uses existing scopes only.
 */
var TRAVEL_FACTORY_RUNTIME_REPAIR_VERSION = 'TRAVEL_FACTORY_RUNTIME_REPAIR_V1_20260820';
var TRAVEL_FACTORY_DRYWRITER_KEY = 'DRYWRITER_WEBAPP_URL';

function inspectTravelFactoryRuntimeRepair() {
  var ss = SpreadsheetApp.getActiveSpreadsheet();
  var appId = travelFactoryConfigValue_('APP_ID');
  var configUrl = String(travelFactoryConfigValue_(TRAVEL_FACTORY_DRYWRITER_KEY) || '').trim();
  var propertyUrl = String(PropertiesService.getScriptProperties().getProperty(TRAVEL_FACTORY_DRYWRITER_KEY) || '').trim();
  var triggers = ScriptApp.getProjectTriggers().map(function(t) {
    return { handler: String(t.getHandlerFunction ? t.getHandlerFunction() : ''), uid: String(t.getUniqueId ? t.getUniqueId() : ''), eventType: String(t.getEventType ? t.getEventType() : ''), source: String(t.getTriggerSource ? t.getTriggerSource() : '') };
  });
  return {
    ok: true,
    version: TRAVEL_FACTORY_RUNTIME_REPAIR_VERSION,
    spreadsheetId: ss.getId(),
    spreadsheetName: ss.getName(),
    appId: appId,
    scriptId: ScriptApp.getScriptId(),
    configDryWriterUrlPresent: !!configUrl,
    scriptPropertyDryWriterUrlPresent: !!propertyUrl,
    dryWriterUrlMatches: !!configUrl && configUrl === propertyUrl,
    processTaskQueueTriggerCount: triggers.filter(function(t) { return t.handler === 'processTaskQueue'; }).length,
    triggers: triggers,
    at: new Date().toISOString()
  };
}

function repairTravelFactoryRuntimeConfig() {
  var appId = String(travelFactoryConfigValue_('APP_ID') || '').trim();
  if (appId !== 'APP_TRAVEL') throw new Error('APP_ID_MISMATCH_EXPECTED_APP_TRAVEL:' + appId);
  var url = String(travelFactoryConfigValue_(TRAVEL_FACTORY_DRYWRITER_KEY) || '').trim();
  if (!/^https:\/\/script\.google\.com\/macros\/s\/[^/]+\/exec(?:\?.*)?$/.test(url)) throw new Error('INVALID_OR_MISSING_CONFIG_DRYWRITER_WEBAPP_URL');
  var props = PropertiesService.getScriptProperties();
  props.setProperty(TRAVEL_FACTORY_DRYWRITER_KEY, url);
  if (String(props.getProperty(TRAVEL_FACTORY_DRYWRITER_KEY) || '').trim() !== url) throw new Error('SCRIPT_PROPERTY_READBACK_MISMATCH');
  return inspectTravelFactoryRuntimeRepair();
}

function travelFactoryConfigValue_(key) {
  var sh = SpreadsheetApp.getActiveSpreadsheet().getSheetByName('CONFIG');
  if (!sh) throw new Error('SHEET_MISSING:CONFIG');
  var last = sh.getLastRow();
  if (last < 2) return '';
  var values = sh.getRange(2, 1, last - 1, 2).getValues();
  for (var i = 0; i < values.length; i++) if (String(values[i][0] || '').trim() === key) return values[i][1];
  return '';
}
