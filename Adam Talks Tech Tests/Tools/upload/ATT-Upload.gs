/**
 * ATT Test Results receiver (Google Apps Script) - v2, Nov 22 2026 (auto-logging)
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
 *     Then run  importPugetFolder  once: it reads every Puget CSV already in the
 *     Drive folder "Puget Results" into a "Puget Detail" tab (every single test).
 *  4. Deploy > New deployment > Web app. Execute as: Me. Who has access: Anyone.
 *     ("Anyone" only means it can be reached; every request must carry a valid
 *      signature made with ATT_KEY or it's thrown away.) Copy the /exec URL.
 *
 * WHAT IT CAN DO: add a row to Raw Results, save a zip in ATT Test Results, copy any
 * Puget CSV in that zip into Puget Results/<Mac>, and add its tests to Puget Detail.
 * It never sends anything back except "ok" or "denied".
 *
 * v2 AUTO-LOGGING: a card line   LOG | New Tests | <column header> | <value>
 * (or the LM Studio style   New Tests  BJ-BK (label):<tab>v1<tab>v2 ) is written into that
 * Mac's row. The row comes from the "Mac Map" tab (Mac ID -> row). Every write keeps the old
 * value in the cell's note and gets a line in the "Auto Log" tab. A card with a warning
 * (WARM-UP, don't log, NOT CLEAN, NOT ANE, a line starting !!, run it again, WRONG PROJECT)
 * is HELD: logged in Auto Log, nothing written. Queue and backfill uploads are skipped
 * (each test already uploads on its own).
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
  if (!props.getProperty('ATT_PUGET_FOLDER_ID')) {
    var pf = DriveApp.getFoldersByName('Puget Results');
    props.setProperty('ATT_PUGET_FOLDER_ID', pf.hasNext() ? pf.next().getId() : DriveApp.createFolder('Puget Results').getId());
  }
  pugetSheet_(ss);
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
    // Nov 22: signed live read of both result tabs for Run This Next (the published CSV can lag minutes)
    if (d.kind === 'sheet') {
      var ss = SpreadsheetApp.openById(props.getProperty('ATT_SHEET_ID'));
      var out = 'ok sheet\n';
      ['Main Results', 'New Tests'].forEach(function (name) {
        var v = ss.getSheetByName(name).getDataRange().getDisplayValues();
        out += '=====ATT-TAB ' + name + '=====\n' + v.map(function (r) {
          return r.map(function (c) { c = String(c); return /[",\n\r]/.test(c) ? '"' + c.replace(/"/g, '""') + '"' : c; }).join(',');
        }).join('\n') + '\n';
      });
      return reply_(out);
    }
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
        try { pugetFromZip_(blob, d, props); } catch (pe) { console.error(pe); }
      }
      var summary = '';
      if (d.summary_b64) summary = Utilities.newBlob(Utilities.base64Decode(d.summary_b64)).getDataAsString('UTF-8').slice(0, 45000);
      sh.appendRow([new Date(), cell_(d.mac), cell_(/^[0-9a-f]{8}$/.test(d.macid || '') ? d.macid : ''), cell_(d.test), cell_(d.mackind), cell_(d.when),
                    Number(d.files) || 0, link, cell_(d.summary_file), cell_(summary), cell_(d.note)]);
      try { autoLog_(d, summary, link); } catch (ae) { console.error(ae); }
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
  if (typeof v === 'number' || v instanceof Date) return v;
  var s = (v === undefined || v === null) ? '' : String(v).slice(0, 45000);
  return /^[=+\-@\t\r]/.test(s) ? "'" + s : s;
}
function name_(v) { return String(v || '').replace(/[^A-Za-z0-9 ._()'+-]/g, '').slice(0, 100); }
function sub_(parent, n) {
  var it = parent.getFoldersByName(n);
  return it.hasNext() ? it.next() : parent.createFolder(n);
}

// ---------------- Puget Bench CSVs -> "Puget Detail" (one row per individual test) ----------------
var PUGET_TAB = 'Puget Detail';
var PUGET_COLS = ['Key', 'Imported', 'Mac', 'Mac ID', 'Run date', 'Benchmark', 'Bench version', 'App', 'App version',
  'Model ID', 'CPU', 'CPU cores', 'GPU cores', 'RAM (GB)', 'macOS', 'Power source', 'Puget upload ID',
  'Test', 'Group', 'Units', 'Run 1', 'Run 2', 'Run 3', 'CSV file'];

function pugetSheet_(ss) {
  var sh = ss.getSheetByName(PUGET_TAB) || ss.insertSheet(PUGET_TAB);
  if (sh.getLastRow() === 0) { sh.appendRow(PUGET_COLS); sh.setFrozenRows(1); }
  return sh;
}

// Run once by hand: imports every Puget CSV in the "Puget Results" folder (and its subfolders).
function importPugetFolder() {
  var props = PropertiesService.getScriptProperties();
  var root = DriveApp.getFolderById(props.getProperty('ATT_PUGET_FOLDER_ID'));
  var n = 0, stack = [root];
  while (stack.length) {
    var f = stack.pop(), files = f.getFiles(), subs = f.getFolders();
    while (subs.hasNext()) stack.push(subs.next());
    while (files.hasNext()) {
      var file = files.next();
      if (!/\.csv$/i.test(file.getName())) continue;
      n += importPugetText_(file.getBlob().getDataAsString('UTF-8'), file.getName(), '', '', file.getUrl());
    }
  }
  Logger.log('Added ' + n + ' Puget test rows.');
}

function pugetFromZip_(zipBlob, d, props) {
  var parts = Utilities.unzip(zipBlob), dest = null;
  for (var i = 0; i < parts.length; i++) {
    var b = parts[i], nm = String(b.getName()).split('/').pop();
    if (!/puget.*\.csv$/i.test(nm)) continue;
    var text = b.getDataAsString('UTF-8');
    if (!/^Benchmark Name,Puget Bench/m.test(text)) continue;
    if (!dest) dest = sub_(DriveApp.getFolderById(props.getProperty('ATT_PUGET_FOLDER_ID')),
                           (name_(d.mac) || 'Unknown Mac') + (/^[0-9a-f]{8}$/.test(d.macid || '') ? ' [' + d.macid + ']' : ''));
    var url = dest.getFilesByName(nm).hasNext() ? dest.getFilesByName(nm).next().getUrl()
                                                 : dest.createFile(Utilities.newBlob(text, 'text/csv', nm)).getUrl();
    importPugetText_(text, nm, name_(d.mac), /^[0-9a-f]{8}$/.test(d.macid || '') ? d.macid : '', url);
  }
}

// Parses one Puget CSV and appends its tests. Skips a run that's already in the tab. Returns rows added.
function importPugetText_(text, fileName, mac, macid, url) {
  var rows = Utilities.parseCsv(text), kv = {}, sys = {}, tests = [], inResults = false;
  rows.forEach(function (r) {
    r = r.map(function (c) { return String(c).trim(); });
    if (!r[0]) return;
    if (r[0] === 'Test' && r[1] === 'Setting') { inResults = true; return; }
    if (inResults) { tests.push(r); return; }
    if (['System', 'OS', 'CPU', 'Motherboard', 'Memory', 'GPU', 'Power'].indexOf(r[0]) >= 0) {
      if (r[0] === 'Power') sys['Power ' + r[1]] = r[2]; else sys[r[0]] = r;
    } else kv[r[0]] = r[1];
  });
  if (!tests.length || !kv['Benchmark Name']) return 0;
  var m = String(fileName).match(/(\d{4}-\d{2}-\d{2})_(\d{2})-(\d{2})-(\d{2})/);
  var runDate = m ? m[1] + ' ' + m[2] + ':' + m[3] + ':' + m[4] : '';
  var model = sys.Motherboard ? sys.Motherboard[2] : '';
  var key = [kv['Benchmark Name'], kv['Application Version'], runDate, model, kv['Upload ID'] || '', tests.length].join('|');
  var ss = SpreadsheetApp.openById(PropertiesService.getScriptProperties().getProperty('ATT_SHEET_ID'));
  var sh = pugetSheet_(ss);
  var last = sh.getLastRow();
  if (last > 1) {
    var keys = sh.getRange(2, 1, last - 1, 1).getValues();
    for (var i = 0; i < keys.length; i++) if (keys[i][0] === key) return 0;
  }
  var base = [key, new Date(), mac || '', macid || '', runDate, kv['Benchmark Name'], kv['Benchmark Version'],
    kv['Application Name'], kv['Application Version'], model,
    sys.CPU ? sys.CPU[2] : '', sys.CPU ? sys.CPU[3] : '', sys.GPU ? sys.GPU[3] : '',
    sys.Memory ? sys.Memory[2] : '', sys.OS ? sys.OS.slice(2).join(' ') : '', sys['Power Power Source'] || '', kv['Upload ID'] || ''];
  var out = tests.map(function (t) {
    return base.concat([t[0], t[1] || '', t[2] || '', num_(t[3]), num_(t[4]), num_(t[5]), url || fileName]).map(cell_);
  });
  sh.getRange(sh.getLastRow() + 1, 1, out.length, PUGET_COLS.length).setValues(out);
  return out.length;
}
function num_(v) { if (v === undefined || v === '') return ''; var n = Number(v); return isNaN(n) ? v : n; }

// ---------------- v2: auto-logging into the Mac's row ----------------
var AUTO_TAB = 'Auto Log', MAP_TAB = 'Mac Map';
var HOLD_RE = /WARM-UP|don't log|NOT CLEAN|NOT ANE|^!!.*|run it again|WRONG PROJECT/m;

function autoLog_(d, summary, link) {
  if (!summary || /queue|backfill|^ping$/i.test(String(d.test || ''))) return;
  var items = parseLogLines_(summary);
  if (!items.length) return;
  var ss = SpreadsheetApp.openById(PropertiesService.getScriptProperties().getProperty('ATT_SHEET_ID'));
  var macid = /^[0-9a-f]{8}$/.test(d.macid || '') ? d.macid : '';
  var rows = macRows_(ss, macid);
  var hold = summary.match(HOLD_RE);
  var log = autoSheet_(ss), when = Utilities.formatDate(new Date(), 'America/Chicago', 'MMM d h:mm a');
  var out = [];
  items.forEach(function (it) {
    var sh = ss.getSheetByName(it.tab), col = 0, head = it.header || '', status;
    if (!sh) status = 'no tab ' + it.tab;
    else {
      col = it.col || findCol_(sh, it.header);
      if (col && !head) head = String(sh.getRange(2, col).getValue());
      var row = rows[it.tab];
      if (!col) status = 'no column matches "' + it.header + '"';
      else if (!row) status = 'Mac ID ' + (macid || '?') + ' not in Mac Map';
      else if (hold) status = 'HELD (card says: ' + hold[0].slice(0, 80) + ')';
      else if (/^[\s\/\-?]*$|^n\/a$/i.test(it.value)) status = 'no value, skipped';
      else {
        var cell = sh.getRange(row, col), old = String(cell.getDisplayValue());
        if (old === it.value) status = 'same as sheet';
        else {
          cell.setValue(val_(it.value));
          cell.setNote('Auto-logged ' + when + ' from ' + (d.test || '') + (old ? '\nwas: ' + old : '') + (link ? '\n' + link : ''));
          status = old ? 'REPLACED (was ' + old + ')' : 'written';
        }
      }
    }
    out.push([new Date(), cell_(d.mac), macid, cell_(d.test), it.tab, (rows[it.tab] || ''), col ? letter_(col) : '', cell_(head), cell_(it.value), status, link || '']);
  });
  if (out.length) log.getRange(log.getLastRow() + 1, 1, out.length, out[0].length).setValues(out);
}

function parseLogLines_(text) {
  var items = [];
  String(text).split(/\r?\n/).forEach(function (l) {
    var m = l.match(/^\s*LOG \| (Main Results|New Tests) \| (.+?) \| (.*?)\s*$/);
    if (m) { items.push({ tab: m[1], header: m[2].trim(), value: m[3].trim() }); return; }
    m = l.match(/^\s*(Main Results|New Tests)\s+([A-Z]{1,2})(?:-([A-Z]{1,2}))?\s*\(.*?\):\t(.*)$/);
    if (m) {
      var c0 = colNum_(m[2]), c1 = m[3] ? colNum_(m[3]) : c0, vals = m[4].split('\t');
      for (var i = 0; i < vals.length && c0 + i <= c1; i++) items.push({ tab: m[1], col: c0 + i, value: vals[i].trim() });
    }
  });
  return items;
}

// Mac Map: A Mac ID | B Mac name | C New Tests row | D Main Results row | E note
function macRows_(ss, macid) {
  var sh = ss.getSheetByName(MAP_TAB);
  if (!sh || !macid) return {};
  var v = sh.getDataRange().getValues();
  for (var i = 1; i < v.length; i++) if (String(v[i][0]).trim() === macid)
    return { 'New Tests': Number(v[i][2]) || 0, 'Main Results': Number(v[i][3]) || 0 };
  return {};
}

function findCol_(sh, header) {
  if (!header) return 0;
  var norm = function (s) { return String(s).toLowerCase().replace(/\s+/g, ' ').trim(); };
  var h = norm(header), row = sh.getRange(2, 1, 1, sh.getLastColumn()).getValues()[0];
  for (var i = 0; i < row.length; i++) if (norm(row[i]) === h) return i + 1;
  for (i = 0; i < row.length; i++) if (row[i] && norm(row[i]).indexOf(h) === 0) return i + 1;
  return 0;
}

function autoSheet_(ss) {
  var sh = ss.getSheetByName(AUTO_TAB) || ss.insertSheet(AUTO_TAB);
  if (sh.getLastRow() === 0) {
    sh.appendRow(['Received', 'Mac', 'Mac ID', 'Test', 'Tab', 'Row', 'Column', 'Column header', 'Value', 'What happened', 'Logs (zip)']);
    sh.setFrozenRows(1);
  }
  return sh;
}
function colNum_(a) { var n = 0; for (var i = 0; i < a.length; i++) n = n * 26 + (a.charCodeAt(i) - 64); return n; }
function letter_(n) { var s = ''; while (n > 0) { var m = (n - 1) % 26; s = String.fromCharCode(65 + m) + s; n = Math.floor((n - 1) / 26); } return s; }
function val_(v) { return /^-?\d+(\.\d+)?$/.test(v) ? Number(v) : cell_(v); }

// Run by hand to test without a Mac: Run > testAutoLog (writes nothing; shows what it would parse)
function testAutoLog() {
  Logger.log(JSON.stringify(parseLogLines_('LOG | New Tests | CPU memory bandwidth | 279.1\nNew Tests  BJ-BK (Whisper):\t12.3s / 48x\t9.1s / 66x / ANE 1.2 W')));
}

// Claude check (Nov 22): fake Mac ID, so nothing in the results tabs changes; adds one Auto Log line
function testAutoLogLive() {
  autoLog_({ mac: 'TEST (Claude check)', macid: '00000000', test: 'att-bandwidth.zsh' }, 'LOG | New Tests | CPU memory bandwidth, STREAM triad | 1.0', '');
}
