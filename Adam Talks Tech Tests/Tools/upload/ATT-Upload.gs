/**
 * ATT Test Results receiver (Google Apps Script) - v1, Nov 21 2026
 *
 * Paste this into the Mac Tests sheet: Extensions > Apps Script.
 * It contains NO secrets. The key lives in Project Settings > Script Properties.
 *
 * ONE-TIME SETUP
 *  1. Paste this file, save.
 *  2. Project Settings > Script Properties > add ATT_KEY = the 64-character key
 *     from:  zsh Tools/att-upload.zsh newkey
 *  3. Run the function  setup  once (Run button). Approve the permissions.
 *     It makes the "Raw Results" tab and the Drive folder "ATT Test Results".
 *  4. Deploy > New deployment > Web app. Execute as: Me. Who has access: Anyone.
 *     ("Anyone" only means it can be reached; every request must carry a valid
 *      signature made with ATT_KEY or it's thrown away.) Copy the /exec URL.
 *
 * WHAT IT CAN DO: add a row to Raw Results and save a zip in ATT Test Results.
 * It never sends anything back except "ok" or "denied".
 */

var MAX_BODY = 40 * 1024 * 1024;      // bytes of JSON
var MAX_AGE_S = 300;                  // signature must be under 5 minutes old
var TAB = 'Raw Results';

function setup() {
  var props = PropertiesService.getScriptProperties();
  var ss = SpreadsheetApp.getActiveSpreadsheet();
  var sh = ss.getSheetByName(TAB) || ss.insertSheet(TAB);
  if (sh.getLastRow() === 0) {
    sh.appendRow(['Received', 'Mac', 'Mac ID', 'Test', 'Mac kind', 'Test finished', 'Files', 'Logs (zip)', 'Summary file', 'Summary', 'Note']);
    sh.setFrozenRows(1);
  }
  var folderId = props.getProperty('ATT_FOLDER_ID');
  if (!folderId) {
    var folder = DriveApp.createFolder('ATT Test Results');
    props.setProperty('ATT_FOLDER_ID', folder.getId());
  }
  props.setProperty('ATT_SHEET_ID', ss.getId());
  if (!/^[0-9a-f]{64}$/.test(props.getProperty('ATT_KEY') || '')) {
    throw new Error('Add ATT_KEY (64 hex characters) in Project Settings > Script Properties, then run setup again.');
  }
  Logger.log('Ready. Now Deploy > New deployment > Web app.');
}

function doGet() { return reply_('denied'); }

function doPost(e) {
  try {
    var props = PropertiesService.getScriptProperties();
    var key = props.getProperty('ATT_KEY') || '';
    if (!/^[0-9a-f]{64}$/.test(key)) return reply_('denied');
    if (!e || !e.postData || !e.parameter) return reply_('denied');
    var body = e.postData.contents || '';
    var ts = String(e.parameter.ts || ''), sig = String(e.parameter.sig || '').toLowerCase();
    if (!/^\d{9,11}$/.test(ts) || !/^[0-9a-f]{64}$/.test(sig)) return reply_('denied');
    if (body.length > MAX_BODY) return reply_('denied');
    if (Math.abs(Date.now() / 1000 - Number(ts)) > MAX_AGE_S) return reply_('denied');

    var mac = Utilities.computeHmacSha256Signature(ts + '\n' + body, key, Utilities.Charset.UTF_8);
    if (!safeEqual_(hex_(mac), sig)) return reply_('denied');

    var cache = CacheService.getScriptCache();          // no replays
    if (cache.get('sig_' + sig)) return reply_('denied');
    cache.put('sig_' + sig, '1', 900);

    var d = JSON.parse(body);
    var lock = LockService.getScriptLock();
    lock.waitLock(30000);
    try {
      var sh = SpreadsheetApp.openById(props.getProperty('ATT_SHEET_ID')).getSheetByName(TAB);
      var link = '';
      if (d.kind === 'result' && d.zip_b64) {
        var root = DriveApp.getFolderById(props.getProperty('ATT_FOLDER_ID'));
        var macFolder = sub_(root, (name_(d.mac) || 'Unknown Mac') + (/^[0-9a-f]{8}$/.test(d.macid || '') ? ' [' + d.macid + ']' : ''));
        var fname = name_(d.test || 'test') + ' - ' + Utilities.formatDate(new Date(), 'America/Chicago', 'yyyy-MM-dd HH-mm-ss') + '.zip';
        var blob = Utilities.newBlob(Utilities.base64Decode(d.zip_b64), 'application/zip', fname);
        link = macFolder.createFile(blob).getUrl();
      }
      var summary = '';
      if (d.summary_b64) summary = Utilities.newBlob(Utilities.base64Decode(d.summary_b64)).getDataAsString('UTF-8').slice(0, 45000);
      sh.appendRow([new Date(), cell_(d.mac), cell_(/^[0-9a-f]{8}$/.test(d.macid || '') ? d.macid : ''), cell_(d.test), cell_(d.mackind), cell_(d.when),
                    Number(d.files) || 0, link, cell_(d.summary_file), cell_(summary), cell_(d.note)]);
    } finally { lock.releaseLock(); }
    return reply_(d.kind === 'ping' ? 'ok ping received' : 'ok sent to the Mac Tests sheet + Drive');
  } catch (err) {
    console.error(err);
    return reply_('denied');
  }
}

function reply_(s) { return ContentService.createTextOutput(s).setMimeType(ContentService.MimeType.TEXT); }
function hex_(bytes) { return bytes.map(function (b) { return ('0' + (b & 255).toString(16)).slice(-2); }).join(''); }
function safeEqual_(a, b) {
  if (a.length !== b.length) return false;
  var r = 0; for (var i = 0; i < a.length; i++) r |= a.charCodeAt(i) ^ b.charCodeAt(i);
  return r === 0;
}
// Text going into a cell can't start a formula (=, +, -, @) and is length-capped
function cell_(v) {
  var s = (v === undefined || v === null) ? '' : String(v).slice(0, 45000);
  return /^[=+\-@\t\r]/.test(s) ? "'" + s : s;
}
function name_(v) { return String(v || '').replace(/[^A-Za-z0-9 ._()'+-]/g, '').slice(0, 100); }
function sub_(parent, n) {
  var it = parent.getFoldersByName(n);
  return it.hasNext() ? it.next() : parent.createFolder(n);
}
