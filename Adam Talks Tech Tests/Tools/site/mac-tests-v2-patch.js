// adamtalks.tech/mac-tests (page 202) v2 patch, Nov 22 2026. NOT LIVE until Adam approves.
// Adds the sheet's New Tests tab to the page: Memory (RAM) and Heat categories, bandwidth,
// responsiveness, stacker, Safari RAM, HandBrake, Qwen 9B/27B, Draw Things, Whisper GPU,
// Logic @32, War Thunder. New Tests rows are matched to the same Mac chips (NCFG below).
// Tested Nov 22 against the live sheet: 30 Macs, 68 tests, no duplicate chips, syntax OK.
//
// How to apply (Claude does this): in wp-admin's editor for page 202, take
// wp.data.select('core/editor').getEditedPostContent() as c, run attMacTestsV2(c), and save the
// result as a draft page first for Adam to preview.
function attMacTestsV2(c) {
  const rep = (a, b) => { if (c.split(a).length !== 2) throw new Error('anchor ' + a.slice(0, 40)); c = c.replace(a, () => b); };
  rep("'M4 Max Mac Studio':{n:'M4 Max Mac Studio',old:1}\n};", `'M4 Max Mac Studio':{n:'M4 Max Mac Studio',old:1},
'M5 Max MacBook Pro 14" PROLED XDR Space Black':{n:'M5 Max MacBook Pro 14" PROLED'},'M5 Max MacBook Pro 16" PROLED XDR Space Black':{n:'M5 Max MacBook Pro 16" PROLED'},'M6 iMac 24" Silver':{n:'M6 iMac 24"'}
};
/* Nov 22 2026: the New Tests tab (RAM, bandwidth, heat, local AI, HandBrake...) merged into the same Macs. Its row names map to the names above. */
var NTG=1327339876;
var NCFG={'M5 Pro Mac mini (15-core)':{n:'M5 Pro Mac mini'},'M5 Pro Mac mini (18-core upgraded)':{n:'M5 Pro Mac mini, 18-core'},'M5 MacBook Pro 14"':{n:'M5 MacBook Pro 14"',x:'Nov 2026 run'},'M5 Max PROLED MacBook Pro 14"':{n:'M5 Max MacBook Pro 14" PROLED'},'M5 Max PROLED MacBook Pro 16"':{n:'M5 Max MacBook Pro 16" PROLED'},'M5 Pro PROLED MacBook Pro 14"':{n:'M5 Pro MacBook Pro 14" PROLED'},'M5 MacBook Air 13" Sky Blue':{n:'M5 MacBook Air 13"',x:'8-core GPU'}};`);
  rep("{k:'everyday',n:'Everyday speed'},", "{k:'everyday',n:'Everyday speed'},{k:'memory',n:'Memory (RAM)'},");
  rep("{k:'storage',n:'Storage speed'}", "{k:'heat',n:'Heat and sustained speed'},{k:'storage',n:'Storage speed'}");
  rep("if(f=='d')return v.toFixed(1);", "if(f=='d')return v.toFixed(1);if(f=='pct')return v.toFixed(1)+'%';if(f=='gb')return v.toFixed(1)+' GB';");
  rep("TESTS.forEach(function(t){t.i=findCol(head,t)});", "TESTS.forEach(function(t){t.i=t.nt?-1:findCol(head,t)});");
  rep("{k:'cpn',c:'gaming'", `{k:'resp',c:'memory',nt:1,pre:1,col:'Responsiveness LOADED score',t:'App switching with 80 Safari tabs open',n:'How much of its app-switching speed the Mac keeps with 80 tabs open. 1000 means no slowdown. '+HI,f:'n',free:1},
{k:'stack',c:'memory',nt:1,pre:1,col:'Stacker: FCP 3-min 4K export',t:'Final Cut export with everything open',n:'80 Safari tabs, Final Cut, Numbers and a local AI model all open, then a 3-minute 4K export. '+LO,f:'t',low:1},
{k:'saf80',c:'memory',nt:1,pre:1,col:'App RAM: Safari 20 / 80 tabs',part:1,t:'Memory Safari wants with 80 tabs',n:'Activity Monitor memory for Safari and its pages, nothing else open. '+LO,f:'gb',low:1},
{k:'bwc',c:'memory',nt:1,pre:1,col:'CPU memory bandwidth, STREAM triad',t:'Memory bandwidth, CPU',n:'STREAM triad, GB per second. '+HI,f:'d',free:1},
{k:'bwg',c:'memory',nt:1,pre:1,col:'GPU memory bandwidth, Metal copy',t:'Memory bandwidth, GPU',n:'Metal copy, GB per second. '+HI,f:'d'},
{k:'sus',c:'heat',nt:1,pre:1,col:'Sustained drop',t:'Slowdown under sustained load',n:'Blender CPU three times back to back: how much slower the 3rd run is than the 1st. '+LO,f:'pct',low:1,free:1},
{k:'hbx',c:'video',nt:1,col:'x265 CPU encode time',t:'HandBrake, x265 (CPU)',n:'4K to 1080p, HandBrake Fast 1080p30. '+LO,f:'t',low:1},
{k:'hbv',c:'video',nt:1,col:'VideoToolbox H.265 encode time',t:'HandBrake, VideoToolbox (media engine)',n:'4K to 1080p, HandBrake Fast 1080p30. '+LO,f:'t',low:1},
{k:'qw9',c:'ai',nt:1,col:'Qwen 9B generation (tok/s), Roman 10 paragraphs',t:'Qwen 3.5 9B, writing speed',n:'Local AI that fits on every Mac. Tokens per second. '+HI,f:'d'},
{k:'qw27',c:'ai',nt:1,col:'Generation (tok/s), Roman 10 paragraphs',t:'Qwen3.8 27B, writing speed',n:'Bigger local AI. Tokens per second. '+HI,f:'d'},
{k:'dt',c:'ai',nt:1,pre:1,col:'Draw Things standard',t:'Draw Things image (Z-Image Turbo)',n:'1024x1024, 8 steps. Seconds per image. '+LO,f:'t',low:1},
{k:'whg',c:'ai',nt:1,pre:1,col:'Whisper GPU',t:'Whisper transcription, GPU',n:'10 minutes of audio. '+LO,f:'t',low:1},
{k:'lg32',c:'audio',nt:1,pre:1,col:'Logic tracks @32',t:'Logic Pro tracks, low latency (32 buffer)',n:HI,f:'i'},
{k:'wt',c:'gaming',nt:1,pre:1,col:'War Thunder avg fps',t:'War Thunder',n:GAME+HI,f:'d'},
{k:'cpn',c:'gaming'`);
  rep("function load(i){", `function ntv(raw,t){var s=String(raw||'');if(t.part!=null)s=s.split('/')[t.part]||'';s=s.split(/[(|;]/)[0].trim();if(t.f=='t'||t.f=='s2'){var x=secs(s);return x!==null?x:num(s)}return num(s)}
function mergeNT(rows){var h=-1;for(var i=0;i<rows.length;i++){if((rows[i][0]||'').trim()=='Computer Model'){h=i;break}}if(h<0)return;var head=rows[h].map(function(x){return x.trim()});var nts=TESTS.filter(function(t){return t.nt});nts.forEach(function(t){t.ni=findCol(head,t)});
rows.slice(h+1).forEach(function(r){var model=(r[0]||'').trim();if(!model||/^how to/i.test(model))return;var cfg=NCFG[model]||{n:model},ram=gb(r[2]),sd=ssd(r[3]);var id=[cfg.n,ram,sd].join('|')+(cfg.x?'|'+cfg.x:'');var m=null;macs.forEach(function(q){if(q.id==id)m=q});var vals={},any=false;nts.forEach(function(t){var v=t.ni<0?null:ntv(r[t.ni],t);if(v===null||!isFinite(v))v=null;else any=true;vals[t.k]=v});if(!any)return;
if(!m){m={tested:'',lr16:false,name:cfg.n,chip:(r[1]||'').trim(),ram:ram,ssd:sd,x:cfg.x||'',year:0,buy:[],old:false,r:{},any:true};TESTS.forEach(function(t){m.r[t.k]=null});m.type=typeOf(m.name);m.id=id;m.spec=[m.chip,m.ram,m.ssd].filter(Boolean).join(' · ')+(m.x?' · '+m.x:'');macs.push(m)}
nts.forEach(function(t){if(vals[t.k]!==null)m.r[t.k]=vals[t.k]})})}
function loadNT(){var u=['https://docs.google.com/spreadsheets/d/e/'+KEY+'/pub?gid='+NTG+'\\x26single=true\\x26output=csv','https://docs.google.com/spreadsheets/d/'+DOC+'/gviz/tq?tqx=out:csv\\x26gid='+NTG];return fetch(u[0]).then(function(r){if(!r.ok)throw 0;return r.text()}).catch(function(){return fetch(u[1]).then(function(r){if(!r.ok)throw 0;return r.text()})})}
function load(i){`);
  rep("load(0).then(function(t){macs=build(csv(t));", "Promise.all([load(0),loadNT().catch(function(){return null})]).then(function(res){var t=res[0];macs=build(csv(t));if(res[1]){try{mergeNT(csv(res[1]))}catch(e){try{console.warn('Mac Tests: New Tests merge failed',e)}catch(f){}}}macs.sort(function(a,b){return (b.year-a.year)||(a.name<b.name?-1:1)});");
  return c;
}
