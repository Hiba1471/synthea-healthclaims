"""Build dashboard/spend_burden.html -- a page answering one question.

    python3 dashboard/generators/dashboard_data.py
    python3 dashboard/generators/spend_burden.py

THE QUESTION, which is the page's title and its whole structure:

    Where does healthcare spending concentrate by care type, and how does
    member cost burden vary by payer type?

Two halves, so two sections. Section 1 ranks care types and shows how few
reach half of spend. Section 2 compares what members pay under each plan
type, blended and then care type by care type.

Unlike claims_bi.py this is not a console -- there are no slicers and no
navigation. It answers the question and stops. Every number is stated in the
prose as well as drawn, because a reader who only reads the standfirst should
still leave with the answer.

DATA: dashboard/dashboard_data.json, built from the saved result CSVs. The
care-type figures cover DIAGNOSED spend ($72.69B of $99.11B) because a claim
with no diagnosis has no care type; the payer figures cover all spend. Both
denominators are stated on the page rather than left to be discovered.

COLOUR: validated categorical slots for the three payer types (they must be
told apart), a single-hue blue ramp for member-paid share (a magnitude).
Never one hue per care type -- fifteen categorical colours cannot be
distinguished, and the bars already carry identity in their labels.
"""
import json
import os

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
DATA = os.path.join(ROOT, 'dashboard', 'dashboard_data.json')
OUT = os.path.join(ROOT, 'dashboard', 'spend_burden.html')
ART = os.path.join(ROOT, 'dashboard', 'spend_burden.artifact.html')


def payload():
    with open(DATA) as fh:
        d = json.load(fh)
    care = sorted(d['chart2']['care_types'], key=lambda c: -c['billed'])
    by_payer = {}
    for name, rows in d['chart1']['by_payer'].items():
        billed = sum(y['billed'] for y in rows)
        paid = sum(y['member_paid'] for y in rows)
        by_payer[name] = {'billed': billed, 'member_paid': paid,
                          'share': 100 * paid / billed}
    return {'care': care,
            'conditions': d['chart2']['conditions'],
            'payer': by_payer,
            'payer_year': d['chart3'],
            'years': d['chart1']['overall'],
            'diagnosed_total': sum(c['billed'] for c in care),
            'all_billed': sum(y['billed'] for y in d['chart1']['overall']),
            'members': d['chart4']['headline']['Patients']['population'],
            'claims': 68645121}


PAGE = r'''<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Two Care Types, Eleven Times the Burden</title>
<link rel="preconnect" href="https://fonts.googleapis.com">
<link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
<link rel="stylesheet" href="https://fonts.googleapis.com/css2?family=Newsreader:opsz,wght@6..72,400;6..72,500;6..72,600&family=Public+Sans:wght@400;500;600&family=IBM+Plex+Mono:wght@400;500&display=swap">
<style>
:root{
  color-scheme:light;
  --page:#f3f5f8; --card:#ffffff; --raised:#fafbfc;
  --ink:#0d1521; --ink-2:#46566b; --muted:#7c8b9d;
  --rule:#dde4ec; --axis:#c3cedb; --grid:#e8edf3;
  --accent:#2a78d6;
  --d1:#2a78d6; --d2:#eb6834; --d3:#1baf7a;
  --s1:#d8e7fa; --s2:#a9c9f2; --s3:#6ca4e6;
  --s4:#2a78d6; --s5:#1c5cab; --s6:#123f78;
  --shadow:0 1px 2px rgba(13,21,33,.05),0 8px 24px rgba(13,21,33,.05);
}
@media (prefers-color-scheme:dark){
  :root:not([data-theme="light"]){
    color-scheme:dark;
    --page:#0a0f16; --card:#131b25; --raised:#182029;
    --ink:#ffffff; --ink-2:#b8c5d4; --muted:#7d8c9e;
    --rule:#232f3d; --axis:#2f3d4d; --grid:#1b242f;
    --accent:#3987e5;
    --d1:#3987e5; --d2:#d95926; --d3:#199e70;
    --s1:#123f78; --s2:#1c5cab; --s3:#2a78d6;
    --s4:#6ca4e6; --s5:#a9c9f2; --s6:#d8e7fa;
    --shadow:0 1px 2px rgba(0,0,0,.4),0 8px 26px rgba(0,0,0,.3);
  }
}
:root[data-theme="dark"]{
  color-scheme:dark;
  --page:#0a0f16; --card:#131b25; --raised:#182029;
  --ink:#ffffff; --ink-2:#b8c5d4; --muted:#7d8c9e;
  --rule:#232f3d; --axis:#2f3d4d; --grid:#1b242f;
  --accent:#3987e5;
  --d1:#3987e5; --d2:#d95926; --d3:#199e70;
  --s1:#123f78; --s2:#1c5cab; --s3:#2a78d6;
  --s4:#6ca4e6; --s5:#a9c9f2; --s6:#d8e7fa;
  --shadow:0 1px 2px rgba(0,0,0,.4),0 8px 26px rgba(0,0,0,.3);
}
*{box-sizing:border-box;}
body{margin:0;background:var(--page);color:var(--ink);
  font:16px/1.6 "Public Sans",ui-sans-serif,-apple-system,"Segoe UI",system-ui,sans-serif;
  -webkit-font-smoothing:antialiased;padding:44px 22px 72px;}
.wrap{max-width:1020px;margin:0 auto;}

h1{font-family:"Newsreader",Georgia,serif;font-weight:500;font-size:36px;line-height:1.18;
  letter-spacing:-.015em;margin:0 0 14px;text-wrap:balance;max-width:22ch;}
h2{font-family:"Newsreader",Georgia,serif;font-weight:500;font-size:25px;
  letter-spacing:-.01em;margin:0 0 4px;text-wrap:balance;}
h3{font-size:15px;font-weight:600;margin:0 0 2px;letter-spacing:-.005em;}
.meta{font-size:13px;color:var(--muted);margin:0;font-family:"IBM Plex Mono",monospace;}

/* ---- the two answers, stated before anything is drawn ---- */
/* ---- page tabs ---- */
.tabs{display:flex;gap:4px;flex-wrap:wrap;margin:26px 0 30px;
  border-bottom:1px solid var(--rule);}
.tab{background:none;border:none;border-bottom:2px solid transparent;cursor:pointer;
  color:var(--muted);font:500 14px "Public Sans",system-ui;padding:10px 16px;
  margin-bottom:-1px;transition:color .13s,border-color .13s;}
.tab:hover{color:var(--ink-2);}
.tab[aria-current="page"]{color:var(--ink);border-bottom-color:var(--accent);font-weight:600;}
.tab:focus-visible{outline:2px solid var(--accent);outline-offset:-2px;}

/* ---- kpi strip ---- */
.kpis{display:grid;grid-template-columns:repeat(5,1fr);gap:12px;margin:0 0 26px;}
.kpi{background:var(--card);border:1px solid var(--rule);border-radius:11px;
  padding:16px 16px 14px;box-shadow:var(--shadow);}
.kpi .k{font-size:11px;color:var(--muted);margin:0 0 8px;text-transform:uppercase;
  letter-spacing:.06em;font-weight:600;line-height:1.35;}
.kpi .v{font-family:"Newsreader",Georgia,serif;font-weight:600;font-size:30px;line-height:1;
  letter-spacing:-.02em;color:var(--accent);font-variant-numeric:tabular-nums;margin:0;}
.kpi .n{font-size:11.5px;color:var(--muted);margin:6px 0 0;line-height:1.4;}

table{border-collapse:collapse;width:100%;font-size:13px;}
th{text-align:left;color:var(--muted);font-weight:600;font-size:11px;padding:6px 10px 6px 0;
  border-bottom:1px solid var(--axis);text-transform:uppercase;letter-spacing:.04em;}
td{padding:7px 10px 7px 0;border-bottom:1px solid var(--rule);color:var(--ink-2);}
td:first-child{color:var(--ink);}
td.n{text-align:right;font-variant-numeric:tabular-nums;font-family:"IBM Plex Mono",monospace;}
.crumb{display:flex;align-items:center;gap:9px;margin:0 0 12px;font-size:13px;color:var(--ink-2);}
.back{background:var(--raised);border:1px solid var(--rule);color:var(--ink-2);border-radius:7px;
  padding:4px 10px;font:500 12px "Public Sans",system-ui;cursor:pointer;}
.back:hover{color:var(--ink);}
.hint{font-size:12px;color:var(--muted);font-style:italic;}
.bar-hit{cursor:pointer;}
.bar-hit:focus-visible{outline:2px solid var(--accent);}

.answers{display:grid;grid-template-columns:1fr 1fr;gap:14px;margin:0 0 26px;}
.ans{background:var(--card);border:1px solid var(--rule);border-radius:12px;
  padding:22px 24px;box-shadow:var(--shadow);}
.ans .q{font-size:12px;color:var(--muted);margin:0 0 12px;text-transform:uppercase;
  letter-spacing:.07em;font-weight:600;}
.ans .big{font-family:"Newsreader",Georgia,serif;font-weight:600;font-size:44px;
  line-height:1;letter-spacing:-.02em;color:var(--accent);
  font-variant-numeric:tabular-nums;margin:0 0 8px;}
.ans p{margin:0;font-size:15px;color:var(--ink-2);line-height:1.55;}
.ans p strong{color:var(--ink);font-weight:600;}

/* ---- sections ---- */
section{margin-bottom:44px;}
.shead{border-top:2px solid var(--ink);padding-top:12px;margin-bottom:20px;}
.shead .n{font-family:"IBM Plex Mono",monospace;font-size:12px;color:var(--muted);
  margin:0 0 6px;letter-spacing:.04em;}
.shead p{margin:6px 0 0;color:var(--ink-2);font-size:15px;max-width:66ch;}

.fig{background:var(--card);border:1px solid var(--rule);border-radius:12px;
  padding:18px 20px 20px;box-shadow:var(--shadow);margin-bottom:14px;}
.fig .cap{font-size:12.5px;color:var(--muted);margin:0 0 14px;max-width:70ch;line-height:1.5;}
.grid2{display:grid;grid-template-columns:1fr 1fr;gap:14px;}
.scrollx{overflow-x:auto;}
svg{display:block;max-width:100%;}
.note{font-size:12.5px;color:var(--muted);margin:12px 0 0;line-height:1.5;}

.tick{font:400 10.5px "IBM Plex Mono",monospace;fill:var(--muted);}
.lab{font:400 12px "Public Sans",system-ui;fill:var(--ink);}
.val{font:500 11px "IBM Plex Mono",monospace;fill:var(--ink-2);}
.gridline{stroke:var(--grid);stroke-width:1;}
.axisline{stroke:var(--axis);stroke-width:1;}
.dash{stroke:var(--muted);stroke-width:1;stroke-dasharray:3 3;}

.legend{display:flex;gap:14px;flex-wrap:wrap;font-size:12px;color:var(--ink-2);margin:0 0 12px;}
.lk{display:inline-flex;align-items:center;gap:6px;}
.sw{width:10px;height:10px;border-radius:2px;}
.ramp{display:flex;align-items:center;gap:7px;font-size:11px;color:var(--muted);margin:0 0 12px;}
.ramp i{width:22px;height:10px;display:block;font-style:normal;}

.caveat{background:var(--raised);border:1px solid var(--rule);border-left:3px solid var(--d2);
  border-radius:0 10px 10px 0;padding:16px 20px;margin-top:34px;}
.caveat h3{margin-bottom:6px;}
.caveat p{margin:0 0 8px;font-size:14px;color:var(--ink-2);line-height:1.6;max-width:74ch;}
.caveat p:last-child{margin-bottom:0;}

footer{margin-top:38px;padding-top:18px;border-top:1px solid var(--rule);
  font-size:12.5px;color:var(--muted);line-height:1.65;}
code{font-family:"IBM Plex Mono",monospace;font-size:.9em;}

#tip{position:fixed;pointer-events:none;opacity:0;transition:opacity .1s;background:var(--card);
  border:1px solid var(--axis);border-radius:8px;padding:9px 11px;font-size:12.5px;
  color:var(--ink);box-shadow:0 6px 22px rgba(0,0,0,.18);z-index:60;max-width:260px;line-height:1.5;}
#tip b{display:block;margin-bottom:4px;}
#tip i{font-style:normal;color:var(--ink-2);display:block;}

@media (max-width:860px){
  body{padding:28px 14px 48px;}
  h1{font-size:28px;}
  .answers,.grid2{grid-template-columns:1fr;}
  .kpis{grid-template-columns:repeat(auto-fit,minmax(140px,1fr));}
}
@media (prefers-reduced-motion:reduce){*{transition:none!important;}}
</style>
</head>
<body>
<div class="wrap">

<h1>Where does spending concentrate by care type, and how does member burden vary by plan?</h1>
<p class="meta">Calder Health &middot; 68.6M claims &middot; 1.26M members &middot; 2020&ndash;2024</p>

<nav class="tabs" aria-label="Pages">
  <button class="tab" type="button" data-page="overview" aria-current="page">Overview</button>
  <button class="tab" type="button" data-page="care">Care types</button>
  <button class="tab" type="button" data-page="plan">Plan types</button>
  <button class="tab" type="button" data-page="method">How to read this</button>
</nav>

<div id="pages"></div>

<footer>
  <p>Care-type figures cover the <strong id="f1"></strong> of spend that carries a diagnosis;
  plan-type figures cover all <strong id="f2"></strong>. A claim with no resolvable diagnosis has
  no care type, which is why the two denominators differ.</p>
  <p>Member-paid share is member-paid over total <em>paid</em>, not over billed. Every figure
  traces to a query in <code>sql/analysis/</code> and a result file in <code>sql/results/</code>.
  Generated by <code>dashboard/generators/spend_burden.py</code> &mdash; edit the script, not this page.</p>
</footer>
</div>
<div id="tip" role="status" aria-live="polite"></div>

<script>
const D = __DATA__;
const NS='http://www.w3.org/2000/svg';
const money=v=>{const a=Math.abs(v);
  if(a>=1e9)return '$'+(v/1e9).toFixed(a>=1e10?1:2)+'B';
  if(a>=1e6)return '$'+(v/1e6).toFixed(0)+'M';
  return '$'+Math.round(v).toLocaleString('en-US');};
const money0=v=>'$'+Math.round(v).toLocaleString('en-US');
const num=v=>Math.round(v).toLocaleString('en-US');
const pct=v=>v.toFixed(1)+'%';
const esc=s=>String(s).replace(/[&<>"]/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;'}[c]));

const BINS=[{max:10,c:'var(--s1)',l:'<10%'},{max:15,c:'var(--s2)',l:'10-15%'},
 {max:20,c:'var(--s3)',l:'15-20%'},{max:25,c:'var(--s4)',l:'20-25%'},
 {max:30,c:'var(--s5)',l:'25-30%'},{max:1e9,c:'var(--s6)',l:'30%+'}];
const binOf=s=>(BINS.find(b=>s<b.max)||BINS[5]).c;

function svg(w,h,label){const s=document.createElementNS(NS,'svg');
  s.setAttribute('viewBox','0 0 '+w+' '+h);s.setAttribute('width',w);s.setAttribute('height',h);
  s.setAttribute('role','img');s.setAttribute('aria-label',label);return s;}
function el(t,a,p){const n=document.createElementNS(NS,t);
  for(const k in a)n.setAttribute(k,a[k]);if(p)p.appendChild(n);return n;}
function tx(p,x,y,str,cls,anchor){const t=el('text',{x:x,y:y,class:cls||'tick'},p);
  if(anchor)t.setAttribute('text-anchor',anchor);t.textContent=str;return t;}
const tip=document.getElementById('tip');
function hook(node,title,rows){
  const show=ev=>{tip.innerHTML='<b>'+esc(title)+'</b>'+rows.map(r=>'<i>'+esc(r)+'</i>').join('');
    tip.style.opacity='1';const w=tip.offsetWidth,h=tip.offsetHeight;
    let x=ev.clientX+14,y=ev.clientY+14;
    if(x+w>innerWidth-8)x=ev.clientX-w-14;
    if(y+h>innerHeight-8)y=ev.clientY-h-14;
    tip.style.left=x+'px';tip.style.top=y+'px';};
  node.addEventListener('mouseenter',show);node.addEventListener('mousemove',show);
  node.addEventListener('mouseleave',()=>{tip.style.opacity='0';});
}

/* ---- derived figures used across pages ---- */
const tot=D.diagnosed_total;
let run=0, halfN=0;
D.care.forEach((c,i)=>{run+=c.billed; if(!halfN && run>=0.5*tot) halfN=i+1;});
const lead=D.care[0];
const cm=D.payer['Commercial'], gv=D.payer['Government'], sp=D.payer['Self-Pay / Uninsured'];
const ratio=cm.share/gv.share;
const blended=100*(cm.member_paid+gv.member_paid+sp.member_paid)/D.all_billed;
const top5=100*D.care.slice(0,5).reduce((a,c)=>a+c.billed,0)/tot;

document.getElementById('f1').textContent='$'+(tot/1e9).toFixed(2)+'B';
document.getElementById('f2').textContent='$'+(D.all_billed/1e9).toFixed(2)+'B';

const RAMP='<span>Member-paid share</span>'+
  BINS.map(b=>'<i style="background:'+b.c+'" title="'+b.l+'"></i>').join('')+
  '<span>&lt;10% &rarr; 30%+</span>';

let drill=null;   // care type name when the care page is drilled in

/* ================= chart builders ================= */

function careBars(host, rows, opt){
  opt=opt||{};
  const L=opt.gutter||196, R=opt.right||132, W=opt.width||880, rowH=opt.rowH||29;
  const H=rows.length*rowH+12;
  const s=svg(W,H,opt.label||'billed by category');
  const pw=W-L-R, max=Math.max(...rows.map(r=>r.billed));
  rows.forEach((r,i)=>{
    const y=i*rowH+6, h=rowH-11, w=Math.max(2,pw*r.billed/max);
    const g=el('g',{class:r.drill?'bar-hit':''},s);
    if(r.drill){
      g.setAttribute('tabindex','0'); g.setAttribute('role','button');
      g.setAttribute('aria-label','Show conditions inside '+r.name);
      const go=()=>{drill=r.name; render();};
      g.onclick=go;
      g.onkeydown=e=>{if(e.key==='Enter'||e.key===' '){e.preventDefault();go();}};
    }
    el('rect',{x:L,y:y,width:w,height:h,rx:3,fill:binOf(r.share)},g);
    const maxCh=Math.floor((L-14)/6.6);
    const nm=r.name.length>maxCh?r.name.slice(0,maxCh-1)+'…':r.name;
    tx(g,L-10,y+h/2+4,nm,'lab','end');
    tx(g,L+w+9,y+h/2+4,money(r.billed)+'  ·  '+pct(r.share),'val');
    hook(g,r.name,(r.tip||[]).concat(r.drill?['Click to see the conditions inside']:[]));
  });
  el('line',{x1:L,y1:2,x2:L,y2:rows.length*rowH+4,class:'axisline'},s);
  host.innerHTML=''; host.appendChild(s);
}

function cumulativeCurve(host,W){
  W=W||880;
  const H=250,L=52,R=20,TOP=14,ph=H-TOP-42,pw=W-L-R;
  const s=svg(W,H,'Cumulative share of diagnosed spend down the ranked care types');
  for(let i=0;i<=4;i++){const y=TOP+ph-ph*i/4;
    el('line',{x1:L,y1:y,x2:W-R,y2:y,class:'gridline'},s);
    tx(s,L-8,y+4,(i*25)+'%','tick','end');}
  const yHalf=TOP+ph-ph*0.5;
  el('line',{x1:L,y1:yHalf,x2:W-R,y2:yHalf,class:'dash'},s);
  tx(s,W-R-2,yHalf-7,'half of spend','tick','end');
  let acc=0;
  const pts=D.care.map((c,i)=>{acc+=c.billed;
    return{x:L+pw*(i+0.5)/D.care.length,y:TOP+ph-ph*acc/tot,c:c,cum:100*acc/tot};});
  el('path',{d:'M'+pts.map(p=>p.x+','+p.y).join('L'),fill:'none',
    stroke:'var(--accent)','stroke-width':2.5,'stroke-linejoin':'round'},s);
  pts.forEach((p,i)=>{
    const dot=el('circle',{cx:p.x,cy:p.y,r:i<2?6:4.5,
      fill:i<2?'var(--d2)':'var(--accent)',stroke:'var(--card)','stroke-width':2},s);
    hook(dot,(i+1)+'. '+p.c.care_type,['Own share: '+pct(100*p.c.billed/tot),
      'Cumulative: '+pct(p.cum)]);
    if(i<2)tx(s,p.x,p.y-14,pct(p.cum),'val','middle');
  });
  el('line',{x1:L,y1:TOP+ph,x2:W-R,y2:TOP+ph,class:'axisline'},s);
  const every = pw < 500 ? 3 : 2;
  D.care.forEach((c,i)=>{ if(i%every)return;
    tx(s,L+pw*(i+0.5)/D.care.length,TOP+ph+18,i+1,'tick','middle');});
  tx(s,L+pw/2,H-6,'care types, ranked by spend','tick','middle');
  host.innerHTML=''; host.appendChild(s);
}

function payerBars(host,W){
  W=W||430;
  const order=['Commercial','Government','Self-Pay / Uninsured'];
  const SLOT={'Commercial':'var(--d1)','Government':'var(--d2)','Self-Pay / Uninsured':'var(--d3)'};
  const H=232,L=112,R=54,rowH=54;
  const s=svg(W,H,'Member-paid share by plan type');
  const pw=W-L-R;
  order.forEach((p,i)=>{
    const d=D.payer[p], y=i*rowH+22, h=26, w=Math.max(2,pw*d.share/100);
    const g=el('g',{},s);
    el('rect',{x:L,y:y,width:pw,height:h,rx:4,fill:'var(--grid)'},g);
    el('rect',{x:L,y:y,width:w,height:h,rx:4,fill:SLOT[p]},g);
    tx(g,L-10,y+h/2+4,p.replace(' / Uninsured',''),'lab','end');
    tx(g,L+pw+8,y+h/2+4,pct(d.share),'val');
    hook(g,p,['Members pay: '+pct(d.share),'Total billed: '+money0(d.billed),
      'Paid by members: '+money0(d.member_paid)]);
  });
  const yb=3*rowH+22;
  el('line',{x1:L,y1:yb,x2:L+pw,y2:yb,class:'axisline'},s);
  [0,25,50,75,100].forEach(v=>tx(s,L+pw*v/100,yb+16,v+'%','tick','middle'));
  host.innerHTML=''; host.appendChild(s);
}

function dumbbell(host,n,W){
  W=W||430;
  const rows=D.care.filter(c=>c.share_commercial!=null&&c.share_government!=null)
    .slice().sort((a,b)=>(b.share_commercial-b.share_government)-(a.share_commercial-a.share_government))
    .slice(0,n||10);
  const L=140,R=52,rowH=27,H=rows.length*rowH+30;
  const s=svg(W,H,'Commercial against government member-paid share, by care type');
  const pw=W-L-R;
  [0,50,100].forEach(v=>{const x=L+pw*v/100;
    el('line',{x1:x,y1:6,x2:x,y2:rows.length*rowH+6,class:'gridline'},s);
    tx(s,x,rows.length*rowH+22,v+'%','tick','middle');});
  rows.forEach((c,i)=>{
    const y=i*rowH+rowH/2+2;
    const xc=L+pw*Math.min(100,c.share_commercial)/100;
    const xg=L+pw*Math.min(100,c.share_government)/100;
    const g=el('g',{},s);
    el('line',{x1:xg,y1:y,x2:xc,y2:y,stroke:'var(--axis)','stroke-width':2},g);
    el('circle',{cx:xg,cy:y,r:5,fill:'var(--d2)',stroke:'var(--card)','stroke-width':1.5},g);
    el('circle',{cx:xc,cy:y,r:5,fill:'var(--d1)',stroke:'var(--card)','stroke-width':1.5},g);
    const maxCh=Math.floor((L-12)/6.6);
    const nm=c.care_type.length>maxCh?c.care_type.slice(0,maxCh-1)+'…':c.care_type;
    tx(g,L-9,y+4,nm,'lab','end');
    tx(g,L+pw+7,y+4,'+'+Math.round(c.share_commercial-c.share_government),'val');
    hook(g,c.care_type,['Commercial members pay: '+pct(c.share_commercial),
      'Government members pay: '+pct(c.share_government),
      'Gap: '+(c.share_commercial-c.share_government).toFixed(1)+' points']);
  });
  host.innerHTML=''; host.appendChild(s);
}

function payerLines(host){
  const yrs=D.years.map(y=>y.year);
  const SLOT={'Commercial':'var(--d1)','Government':'var(--d2)','Self-Pay / Uninsured':'var(--d3)'};
  const W=860,H=260,L=52,R=124,TOP=14,ph=H-TOP-40,pw=W-L-R;
  const s=svg(W,H,'Member-paid share by plan type, by year');
  for(let i=0;i<=4;i++){const y=TOP+ph-ph*i/4;
    el('line',{x1:L,y1:y,x2:W-R,y2:y,class:'gridline'},s);
    tx(s,L-8,y+4,(i*25)+'%','tick','end');}
  el('line',{x1:L,y1:TOP+ph,x2:W-R,y2:TOP+ph,class:'axisline'},s);
  yrs.forEach((y,i)=>tx(s,L+pw*(i+0.5)/yrs.length,TOP+ph+18,y,'tick','middle'));
  Object.keys(D.payer_year).forEach(p=>{
    const pts=D.payer_year[p].map((d,i)=>({x:L+pw*(i+0.5)/yrs.length,
      y:TOP+ph-ph*d.member_share/100,d:d}));
    el('path',{d:'M'+pts.map(q=>q.x+','+q.y).join('L'),fill:'none',
      stroke:SLOT[p],'stroke-width':2.5,'stroke-linejoin':'round'},s);
    pts.forEach(q=>{const c=el('circle',{cx:q.x,cy:q.y,r:5,fill:SLOT[p],
      stroke:'var(--card)','stroke-width':2},s);
      hook(c,p+' · '+q.d.year,['Members pay: '+pct(q.d.member_share),
        'Paid per member: '+money0(q.d.member_paid_per_member)]);});
    const last=pts[pts.length-1];
    tx(s,last.x+10,last.y+4,p.replace(' / Uninsured','')+' '+pct(last.d.member_share),'val');
  });
  host.innerHTML=''; host.appendChild(s);
}

function tableOf(head,rows,textCols){
  const tc=new Set(textCols||[]);
  return '<table><thead><tr>'+head.map(h=>'<th>'+esc(h)+'</th>').join('')+'</tr></thead><tbody>'+
    rows.map(r=>'<tr>'+r.map((c,i)=>'<td'+(tc.has(i)?'':' class="n"')+'>'+esc(c)+'</td>').join('')+
    '</tr>').join('')+'</tbody></table>';
}

/* ================= pages ================= */
const PAGES={};

PAGES.overview=()=>({
  html:
  '<div class="kpis">'+
    kpi('Total cost of care', money(D.all_billed), '2020&ndash;2024 &middot; '+num(D.claims)+' claims')+
    kpi('Care types for half of spend', halfN+' of '+D.care.length,
        esc(D.care[0].care_type)+' and '+esc(D.care[1].care_type))+
    kpi('Largest care type', pct(100*lead.billed/tot), esc(lead.care_type)+' &middot; '+money(lead.billed))+
    kpi('Commercial vs government', ratio.toFixed(1)+'&times;', pct(cm.share)+' against '+pct(gv.share))+
    kpi('Member-paid share', pct(blended), money(cm.member_paid+gv.member_paid+sp.member_paid)+' out of pocket')+
  '</div>'+
  '<div class="answers">'+
    ansCard('Concentration by care type', halfN+' of '+D.care.length,
      'care types carry <strong>half</strong> of all diagnosed spend. The largest alone is <strong>'+
      pct(100*lead.billed/tot)+'</strong>.')+
    ansCard('Burden by plan type', ratio.toFixed(1)+'×',
      'more of the bill falls on a <strong>commercial</strong> member than a government one &mdash; <strong>'+
      pct(cm.share)+'</strong> against <strong>'+pct(gv.share)+'</strong> of every dollar paid.')+
  '</div>'+
  '<div class="grid2">'+
    fig('Billed by care type','Bar length is total billed; colour is the share members carry. '+
        'The percentage is printed on every bar, so colour never carries the value alone.',
        '<div class="ramp">'+RAMP+'</div><div class="scrollx"><div id="c1"></div></div>')+
    fig('How few care types reach half','Running total down the ranked list. The dashed line marks 50%.',
        '<div class="scrollx"><div id="c2"></div></div>')+
    fig('Share of the bill members carry, by plan type',
        'Of every dollar paid on a claim, how much came from the member rather than the insurer.',
        '<div class="scrollx"><div id="c3"></div></div>'+
        '<p class="note">Self-pay is 100% by definition. The finding is the gap between the two insured lines.</p>')+
    fig('The same care type, both plan types',
        'One row per care type. The two dots are commercial and government members; the line between them is the gap.',
        '<div class="legend"><span class="lk"><span class="sw" style="background:var(--d1)"></span>Commercial</span>'+
        '<span class="lk"><span class="sw" style="background:var(--d2)"></span>Government</span></div>'+
        '<div class="scrollx"><div id="c4"></div></div>')+
  '</div>',
  draw(){
    careBars(document.getElementById('c1'),
      D.care.map(c=>({name:c.care_type,billed:c.billed,share:c.member_share,
        tip:['Total billed: '+money0(c.billed),'Share of diagnosed spend: '+pct(100*c.billed/tot),
             'People affected: '+num(c.members)]})),
      {width:430,gutter:150,right:104,rowH:26,label:'Billed by care type'});
    cumulativeCurve(document.getElementById('c2'),430);
    payerBars(document.getElementById('c3'),430);
    dumbbell(document.getElementById('c4'),10,430);
  }
});

PAGES.care=()=>{
  const rows = drill
    ? D.conditions.filter(c=>c.care_type===drill)
        .map(c=>({name:c.condition,billed:c.billed,share:c.member_share,members:c.members}))
    : D.care.map(c=>({name:c.care_type,billed:c.billed,share:c.member_share,
        members:c.members,drill:true}));
  rows.sort((a,b)=>b.billed-a.billed);
  const shown=rows.slice(0,20);
  return{
    html:
    '<div class="fig"><h3>'+(drill?'Conditions inside '+esc(drill):'Every care type, ranked by spend')+'</h3>'+
    '<p class="cap">'+(drill
      ? esc(drill)+' groups '+rows.length+' condition'+(rows.length===1?'':'s')+
        '. Bar length is total billed; colour is the share members carry.'
      : 'Fifteen care types share $'+(tot/1e9).toFixed(2)+'B of diagnosed spend. '+
        'Click any bar to see the conditions inside it.')+'</p>'+
    '<div class="crumb" id="crumb"></div>'+
    '<div class="ramp">'+RAMP+'</div>'+
    '<div class="scrollx"><div id="cc"></div></div></div>'+
    '<div class="fig"><h3>The figures</h3><p class="cap">'+
    (drill?'Conditions in '+esc(drill):'All fifteen care types')+', largest first.</p><div id="ct"></div></div>',
    draw(){
      const cr=document.getElementById('crumb');
      if(drill){
        const b=document.createElement('button');
        b.type='button'; b.className='back'; b.textContent='← All care types';
        b.onclick=()=>{drill=null;render();};
        cr.appendChild(b);
        const sp2=document.createElement('span');
        sp2.innerHTML='<strong>'+esc(drill)+'</strong>';
        cr.appendChild(sp2);
      } else {
        cr.innerHTML='<span class="hint">Click a bar to drill into its conditions.</span>';
      }
      careBars(document.getElementById('cc'),
        shown.map(r=>({...r, tip:['Total billed: '+money0(r.billed),
          'Members pay: '+pct(r.share),'People affected: '+num(r.members)]})),
        {width:880,gutter:220,right:140,rowH:29});
      document.getElementById('ct').innerHTML=tableOf(
        [drill?'Condition':'Care type','Total billed','Share of diagnosed spend','Members pay','People'],
        rows.map(r=>[r.name,money0(r.billed),
          drill?'—':pct(100*r.billed/tot), pct(r.share), num(r.members)]),[0]);
    }};
};

PAGES.plan=()=>({
  html:
  '<div class="fig"><h3>Share of the bill members carry, by plan type</h3>'+
  '<p class="cap">Blended across the book members pay '+pct(blended)+
  ' of every dollar. That figure describes neither insured line.</p>'+
  '<div class="scrollx"><div id="p1"></div></div></div>'+
  '<div class="fig"><h3>Held across all five years</h3>'+
  '<p class="cap">The gap is not one bad year. Commercial sits near 30% throughout; '+
  'government never rises above 2.8%.</p>'+
  '<div class="scrollx"><div id="p2"></div></div></div>'+
  '<div class="fig"><h3>Every care type, both plan types</h3>'+
  '<p class="cap">Ordered by the size of the gap. Commercial members carry more on every one.</p>'+
  '<div class="legend"><span class="lk"><span class="sw" style="background:var(--d1)"></span>Commercial</span>'+
  '<span class="lk"><span class="sw" style="background:var(--d2)"></span>Government</span></div>'+
  '<div class="scrollx"><div id="p3"></div></div></div>',
  draw(){
    payerBars(document.getElementById('p1'),620);
    payerLines(document.getElementById('p2'));
    dumbbell(document.getElementById('p3'),15,620);
  }
});

PAGES.method=()=>({
  html:
  '<div class="caveat"><h3>One thing that would change the first answer</h3>'+
  '<p>Maternity leads at '+pct(100*lead.billed/tot)+' on a price this dataset inflates by roughly '+
  '8.6&times; against a real-world benchmark. Corrected, it falls to second at 14.7% and chronic '+
  'kidney disease takes first at 19.2% &mdash; without ever being corrected itself, purely because '+
  'everything around it shrank.</p>'+
  '<p><strong>The shape survives; the leader does not.</strong> That a few care types carry most of '+
  'the spend holds under every test run. Which one leads, and by how much, does not. The second '+
  'answer is unaffected: scaling a bill and what was paid on it by the same factor cancels in a '+
  'ratio, so the '+ratio.toFixed(1)+'&times; gap is exactly unchanged.</p></div>'+
  '<div class="fig" style="margin-top:14px;"><h3>Two denominators, on purpose</h3>'+
  '<p class="cap">The two halves of the question do not cover the same money, and the difference '+
  'is not an error.</p>'+
  '<div id="m1"></div>'+
  '<p class="note">A claim with no resolvable diagnosis has no care type, so it cannot appear in a '+
  'care-type ranking. It still has a payer, so it counts in every plan-type figure. Members carry a '+
  'noticeably larger share of that undiagnosed spend (28.3%) than of diagnosed care (17.6%) &mdash; '+
  'nothing in the analysis has looked into why, so treat it as an open question rather than a finding.</p></div>'+
  '<div class="fig"><h3>What each number rests on</h3>'+
  '<p class="cap">Every figure on this page traces to a saved query.</p><div id="m2"></div></div>',
  draw(){
    const dx=D.all_billed-tot;
    document.getElementById('m1').innerHTML=tableOf(
      ['Scope','Billed','Used for'],
      [['Diagnosed spend',money0(tot),'every care-type figure'],
       ['No resolvable diagnosis',money0(dx),'excluded from care types'],
       ['All spend',money0(D.all_billed),'every plan-type figure']],[0,2]);
    document.getElementById('m2').innerHTML=tableOf(
      ['Figure','Value','Query'],
      [['Total cost of care',money(D.all_billed),'q1_cost_drivers.sql'],
       ['Care types for half',halfN+' of '+D.care.length,'q3_concentration.sql'],
       ['Largest care type',pct(100*lead.billed/tot)+' ('+lead.care_type+')','q2_patient_cost_by_care_type.sql'],
       ['Commercial vs government',ratio.toFixed(1)+'×','q2_who_pays.sql'],
       ['Member-paid share',pct(blended),'q2_who_pays.sql'],
       ['Pricing sensitivity','8.6× on maternity','q1_multi_condition_sensitivity.sql']],[0,1,2]);
  }
});

function kpi(k,v,n){
  return '<div class="kpi"><p class="k">'+k+'</p><p class="v">'+v+'</p><p class="n">'+n+'</p></div>';
}
function ansCard(q,big,txt){
  return '<div class="ans"><p class="q">'+q+'</p><p class="big">'+big+'</p><p>'+txt+'</p></div>';
}
function fig(h,cap,body){
  return '<div class="fig"><h3>'+h+'</h3><p class="cap">'+cap+'</p>'+body+'</div>';
}

/* ================= wiring ================= */
let page='overview';
function render(){
  document.querySelectorAll('.tab').forEach(t=>{
    if(t.dataset.page===page)t.setAttribute('aria-current','page');
    else t.removeAttribute('aria-current');});
  const v=PAGES[page]();
  const host=document.getElementById('pages');
  host.innerHTML=v.html;
  v.draw();
}
document.querySelectorAll('.tab').forEach(t=>{
  t.onclick=()=>{page=t.dataset.page; if(page!=='care')drill=null; render();};});
render();
</script>
</body>
</html>
'''


def build():
    return PAGE.replace('__DATA__', json.dumps(payload(), separators=(',', ':')))


def build_artifact(page):
    drop = ['<!doctype html>', '<html lang="en">', '<head>', '</head>',
            '<body>', '</body>', '</html>', '<meta charset="utf-8">',
            '<meta name="viewport" content="width=device-width, initial-scale=1">']
    out = page
    for t in drop:
        out = out.replace(t + '\n', '').replace(t, '')
    return out.strip() + '\n'


if __name__ == '__main__':
    page = build()
    open(OUT, 'w').write(page)
    open(ART, 'w').write(build_artifact(page))
    print('wrote %s (%.0f KB)' % (OUT, os.path.getsize(OUT) / 1024))
