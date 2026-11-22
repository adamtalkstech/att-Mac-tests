// att-sheet-gaps.js (Nov 22 2026) - what a Mac still needs, read from the live Mac Tests sheet.
// Runs on the Mac with:  osascript -l JavaScript att-sheet-gaps.js <MR.csv> <NT.csv> <catalog> <MRrow> <NTrow> <ramGB> "<REDO keys>" "<SKIP keys>"
// Prints:  ROW|<tab>|<model name in that row>
//          WALK|key|step|label
//          HAND|key|step|label|command|why
function csv(t){var r=[],row=[],f='',q=false;for(var i=0;i<t.length;i++){var c=t[i];
  if(q){if(c=='"'){if(t[i+1]=='"'){f+='"';i++}else q=false}else f+=c}
  else if(c=='"')q=true;else if(c==','){row.push(f);f=''}else if(c=='\n'){row.push(f);r.push(row);row=[];f=''}else if(c!='\r')f+=c}
  row.push(f);r.push(row);return r}
function norm(s){return String(s||'').toLowerCase().replace(/\s+/g,' ').trim()}
var BAD=/RERUN|NOT CLEAN|NOT VALID|PROVISIONAL|REDO|WARM-UP|WARM UP/;
function gaps(mrText,ntText,catText,rowMR,rowNT,ram,redo,skip){
  var out=[],tabs={MR:{rows:csv(mrText||''),row:+rowMR},NT:{rows:csv(ntText||''),row:+rowNT}};
  ['MR','NT'].forEach(function(k){var T=tabs[k];T.head=-1;
    for(var i=0;i<Math.min(T.rows.length,10);i++){if(norm(T.rows[i][0])=='computer model'){T.head=i;break}}
    T.h=T.head<0?[]:T.rows[T.head].map(norm);T.r=(T.row>0&&T.rows[T.row-1])||null;
    out.push('ROW|'+k+'|'+(T.r?String(T.r[0]||'').trim():'(no row)'))});
  var R=String(redo||'').split(/\s+/).filter(Boolean),S=String(skip||'').split(/\s+/).filter(Boolean);
  catText.split('\n').forEach(function(line){if(!line.trim()||line.charAt(0)=='#')return;var p=line.split('|');if(p.length<6)return;
    var key=p[0],step=p[1],kind=p[2],minram=+p[3]||0,cols=p[4].split(';'),label=p[5],cmd=p[6]||'';
    if(S.indexOf(key)>=0)return; if(minram&&+ram&&+ram<minram)return;
    var why='';
    if(R.indexOf(key)>=0||R.indexOf('all')>=0)why='redo';
    cols.forEach(function(c){if(why)return;var m=c.match(/^(MR|NT):(.*)$/);if(!m)return;var T=tabs[m[1]];if(!T.r||!T.h.length)return;
      var want=m[2],eq=null,e=want.indexOf('=');if(e>0){eq=want.slice(e+1).trim();want=want.slice(0,e)}
      want=norm(want);var ci=T.h.indexOf(want);if(ci<0){for(var j=0;j<T.h.length;j++){if(T.h[j].indexOf(want)==0){ci=j;break}}}
      if(ci<0)return; var v=String(T.r[ci]||'').trim();
      if(!v||v=='-'||v=='?')why='blank';else if(BAD.test(v))why='marked: '+v.slice(0,40);
      else if(eq!==null&&v.replace(/,/g,'')!=eq)why='old method ('+v+')'});
    if(!why)return;
    out.push(kind=='walk'?['WALK',key,step,label,why].join('|'):['HAND',key,step,label,cmd,why].join('|'))});
  return out.join('\n')}
function run(argv){var rd=function(p){var s=$.NSString.stringWithContentsOfFileEncodingError(p,$.NSUTF8StringEncoding,null);return s.isNil()?'':s.js};
  return gaps(rd(argv[0]),rd(argv[1]),rd(argv[2]),argv[3],argv[4],argv[5],argv[6]||'',argv[7]||'')}
if(typeof module!=='undefined'&&typeof require!=='undefined'){module.exports=gaps;
  if(require.main===module){var fs=require('fs'),a=process.argv.slice(2),r=function(p){try{return fs.readFileSync(p,'utf8')}catch(e){return ''}};
    console.log(gaps(r(a[0]),r(a[1]),r(a[2]),a[3],a[4],a[5],a[6]||'',a[7]||''))}}
