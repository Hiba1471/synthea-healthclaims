"""Build dashboard/claims_bi.html -- the Power BI-styled claims dashboard.

Same data as claims_dashboard.py (dashboard/dashboard_data.json), laid out in
the template the user supplied: left nav rail, KPI strip, card grid, right
filter rail, mint-and-forest identity.

    python3 dashboard/generators/dashboard_data.py
    python3 dashboard/generators/claims_bi.py

TWO SUBSTITUTIONS FROM THE TEMPLATE, both because the claims data has no
equivalent rather than because the template was wrong:

  "Monthly Trends"        -> Monthly, once sql/analysis/q4_monthly_trends.sql
                             has been run against V_CLAIMS_TX_WITH_CARETYPE and
                             its output saved to
                             sql/results/q4_monthly_trends_2020_2024.csv.
                             Until that file exists the view says so and falls
                             back to the yearly figures -- it does not
                             interpolate a month axis out of five annual points.
  "Cancelled Service %"   -> Member-paid share by care type. Nothing in this
                             data is cancelled; every claim is paid in full.
                             Same horizontal-bar-with-percentage form.

COLOUR SPLIT. The mint/forest identity is chrome only -- rails, cards, headings,
KPI figures. Data marks use the validated categorical slots (blue/orange/aqua)
wherever several series must be told apart, and a single-hue teal ramp for
magnitude. A brand palette stretched into five categorical hues is the usual way
a dashboard becomes unreadable for colour-blind viewers; keeping the two jobs
separate avoids it without losing the look.

FILTER APPLICABILITY is unchanged from claims_dashboard.py and for the same
reason -- the saved results sit at different grains. Year drives the KPI strip
and anything with a year axis; care type drives the care-type views; payer type
drives the payer views and switches the SHARE metric elsewhere. Each view states
what reached it rather than pretending everything cross-filters.
"""
import json
import os

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
DATA = os.path.join(ROOT, 'dashboard', 'dashboard_data.json')
OUT = os.path.join(ROOT, 'dashboard', 'claims_bi.html')
ART = os.path.join(ROOT, 'dashboard', 'claims_bi.artifact.html')

PAGE = r'''<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Calder Claims Command Deck</title>
<link rel="preconnect" href="https://fonts.googleapis.com">
<link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
<link rel="stylesheet" href="https://fonts.googleapis.com/css2?family=Bricolage+Grotesque:opsz,wght@12..96,600;12..96,700&family=IBM+Plex+Mono:wght@500;600&family=IBM+Plex+Sans:wght@400;500;600&display=swap">
<style>
/* ---------------------------------------------------------------
   Identity: forest + mint. Neutrals carry a green bias so they read
   as chosen rather than inherited. Every token is declared here in
   the bare :root first, then redefined for the two dark states.
   --------------------------------------------------------------- */
:root{
  color-scheme:light;
  --page:#e8f3ef;
  --rail:#1f4a40;
  --rail-ink:#dcece6;
  --rail-ink-dim:#8fb3a8;
  --rail-active:#ffffff;
  --card:#ffffff;
  --card-edge:#d7e8e2;
  --ink:#0f221e;
  --ink-2:#4a615a;
  --muted:#7b918a;
  --accent:#2f8a75;
  --accent-soft:#e2f1ec;
  --grid:#e4efeb;
  --axis:#c4d8d1;
  /* magnitude ramp: one hue, light -> dark */
  --t1:#d3ece4; --t2:#a9d9cc; --t3:#79c2ae;
  --t4:#4aa78e; --t5:#2f8a75; --t6:#1d6a5a;
  /* identity marks: validated categorical slots, not brand tints */
  --d1:#2a78d6; --d2:#eb6834; --d3:#1baf7a;
  --shadow:0 1px 2px rgba(16,50,42,.06),0 6px 16px rgba(16,50,42,.05);
}
@media (prefers-color-scheme:dark){
  :root:not([data-theme="light"]){
    color-scheme:dark;
    --page:#0c1614;
    --rail:#12241f;
    --rail-ink:#cfe3dc;
    --rail-ink-dim:#7d968e;
    --rail-active:#ffffff;
    --card:#16251f;
    --card-edge:#24382f;
    --ink:#ffffff;
    --ink-2:#bed2cb;
    --muted:#8aa39b;
    --accent:#4fb89c;
    --accent-soft:#1b3129;
    --grid:#223731;
    --axis:#2f4941;
    --t1:#1d6a5a; --t2:#2f8a75; --t3:#4aa78e;
    --t4:#79c2ae; --t5:#a9d9cc; --t6:#d3ece4;
    --d1:#3987e5; --d2:#d95926; --d3:#199e70;
    --shadow:0 1px 2px rgba(0,0,0,.3),0 6px 18px rgba(0,0,0,.28);
  }
}
:root[data-theme="dark"]{
  color-scheme:dark;
  --page:#0c1614; --rail:#12241f; --rail-ink:#cfe3dc; --rail-ink-dim:#7d968e;
  --rail-active:#ffffff; --card:#16251f; --card-edge:#24382f;
  --ink:#ffffff; --ink-2:#bed2cb; --muted:#8aa39b;
  --accent:#4fb89c; --accent-soft:#1b3129; --grid:#223731; --axis:#2f4941;
  --t1:#1d6a5a; --t2:#2f8a75; --t3:#4aa78e;
  --t4:#79c2ae; --t5:#a9d9cc; --t6:#d3ece4;
  --d1:#3987e5; --d2:#d95926; --d3:#199e70;
  --shadow:0 1px 2px rgba(0,0,0,.3),0 6px 18px rgba(0,0,0,.28);
}
*{box-sizing:border-box;}
body{
  margin:0;background:var(--page);color:var(--ink);
  font:15px/1.55 "IBM Plex Sans",ui-sans-serif,-apple-system,"Segoe UI",system-ui,sans-serif;
  -webkit-font-smoothing:antialiased;
}
h1,h2,h3,.kpi-v,.gauge-v{font-family:"Bricolage Grotesque","IBM Plex Sans",system-ui,sans-serif;}

/* ---------------- shell ---------------- */
.shell{display:grid;grid-template-columns:206px minmax(0,1fr) 194px;gap:14px;
  padding:14px;max-width:1560px;margin:0 auto;align-items:start;}

/* ---------------- left rail ---------------- */
.rail{background:var(--rail);border-radius:16px;padding:20px 14px;
  position:sticky;top:14px;min-height:calc(100vh - 28px);
  display:flex;flex-direction:column;gap:6px;}
.brand{display:flex;align-items:center;gap:10px;padding:0 6px 18px;}
.mark{width:34px;height:34px;border-radius:9px;background:var(--rail-ink);
  color:var(--rail);display:grid;place-items:center;font-weight:700;font-size:15px;
  font-family:"Bricolage Grotesque",system-ui,sans-serif;flex:none;}
.brand b{color:var(--rail-active);font-size:14px;font-weight:600;line-height:1.25;
  font-family:"Bricolage Grotesque",system-ui,sans-serif;}
.brand span{display:block;color:var(--rail-ink-dim);font-size:11px;font-weight:400;}
.nav{background:none;border:none;width:100%;text-align:left;cursor:pointer;
  color:var(--rail-ink);font:500 13.5px/1.3 "IBM Plex Sans",system-ui,sans-serif;
  padding:11px 14px;border-radius:10px;transition:background .14s,color .14s;}
.nav:hover{background:rgba(255,255,255,.07);color:var(--rail-active);}
.nav[aria-current="page"]{background:var(--rail-ink);color:var(--rail);font-weight:600;}
.nav:focus-visible{outline:2px solid var(--rail-ink);outline-offset:2px;}
.railfoot{margin-top:auto;padding:14px 8px 0;border-top:1px solid rgba(255,255,255,.1);}
.railfoot p{color:var(--rail-ink-dim);font-size:10.5px;line-height:1.5;margin:0;}

/* ---------------- header ---------------- */
.head{display:flex;justify-content:space-between;align-items:baseline;gap:14px;
  flex-wrap:wrap;margin-bottom:14px;}
.head h1{font-size:21px;margin:0;letter-spacing:-.01em;text-wrap:balance;}
.head p{margin:2px 0 0;color:var(--ink-2);font-size:12.5px;}
.tog{background:var(--card);border:1px solid var(--card-edge);color:var(--ink-2);
  border-radius:8px;padding:6px 12px;font:500 12px "IBM Plex Sans",system-ui,sans-serif;
  cursor:pointer;}
.tog:hover{color:var(--ink);}

/* ---------------- kpi strip ---------------- */
.kpis{display:grid;grid-template-columns:repeat(5,1fr);gap:12px;margin-bottom:14px;}
.kpi{background:var(--card);border:1px solid var(--card-edge);border-radius:13px;
  padding:14px 14px 12px;box-shadow:var(--shadow);text-align:center;}
.kpi-v{font-size:25px;font-weight:700;color:var(--accent);letter-spacing:-.02em;
  font-variant-numeric:tabular-nums;line-height:1.1;}
.kpi-k{font-size:11px;color:var(--ink-2);margin-top:4px;font-weight:500;}
.kpi-n{font-size:10px;color:var(--muted);margin-top:2px;}

/* ---------------- cards ---------------- */
.grid{display:grid;gap:12px;}
.g-3{grid-template-columns:minmax(0,0.92fr) minmax(0,1.3fr) minmax(0,1fr);}
.g-2{grid-template-columns:minmax(0,1fr) minmax(0,1fr);}
.card{background:var(--card);border:1px solid var(--card-edge);border-radius:13px;
  padding:14px 16px 16px;box-shadow:var(--shadow);min-width:0;}
.card h3{font-size:13.5px;margin:0 0 1px;letter-spacing:-.005em;}
.card .cq{font-size:11px;color:var(--muted);margin:0 0 10px;}
.scrollx{overflow-x:auto;}
.applied{font-size:10.5px;color:var(--muted);background:var(--accent-soft);
  border-radius:5px;padding:4px 8px;display:inline-block;margin-bottom:9px;}
.cnote{font-size:11px;color:var(--muted);margin:9px 0 0;line-height:1.45;}
.sub{font-size:11.5px;color:var(--ink-2);border-left:2px solid var(--accent);
  padding:6px 10px;margin:0 0 10px;background:var(--accent-soft);border-radius:0 6px 6px 0;}

/* ---------------- right filter rail ---------------- */
.frail{background:var(--card);border:1px solid var(--card-edge);border-radius:13px;
  padding:14px;position:sticky;top:14px;box-shadow:var(--shadow);}
.frail h4{font:600 11px "IBM Plex Sans",system-ui,sans-serif;color:var(--ink);
  margin:0 0 2px;text-transform:uppercase;letter-spacing:.06em;}
.frail .fd{font-size:10px;color:var(--muted);margin:0 0 7px;line-height:1.35;}
.fgrp{margin-bottom:14px;}
.chips{display:flex;gap:5px;flex-wrap:wrap;}
.chip{border:1px solid var(--card-edge);background:var(--page);color:var(--ink-2);
  border-radius:7px;padding:4px 8px;font:500 11.5px "IBM Plex Sans",system-ui,sans-serif;
  cursor:pointer;transition:background .12s,color .12s,border-color .12s;}
.chip:hover{border-color:var(--accent);}
.chip[aria-pressed="true"]{background:var(--accent);border-color:var(--accent);color:#fff;}
.chip:focus-visible{outline:2px solid var(--accent);outline-offset:2px;}
.reset{background:none;border:none;color:var(--accent);font:500 11.5px "IBM Plex Sans",system-ui;
  cursor:pointer;padding:0;text-decoration:underline;}

/* ---------------- svg ---------------- */
svg{display:block;max-width:100%;}
.tick{font:400 10px "IBM Plex Sans",system-ui;fill:var(--muted);}
.vlab{font:500 10.5px "IBM Plex Mono",ui-monospace,monospace;fill:var(--ink-2);}
.blab{font:400 11px "IBM Plex Sans",system-ui;fill:var(--ink);}
.gridline{stroke:var(--grid);stroke-width:1;}
.axisline{stroke:var(--axis);stroke-width:1;}
.goalline{stroke:var(--muted);stroke-width:1;stroke-dasharray:3 3;}
.gauge-v{font-family:"Bricolage Grotesque",system-ui;font-weight:700;fill:var(--accent);}
.hit{cursor:pointer;}
.hit:focus-visible{outline:2px solid var(--accent);}

.legend{display:flex;gap:12px;flex-wrap:wrap;font-size:11px;color:var(--ink-2);margin:0 0 8px;}
.lk{display:inline-flex;align-items:center;gap:5px;}
.sw{width:9px;height:9px;border-radius:2px;}
.ramp{display:flex;align-items:center;gap:6px;font-size:10px;color:var(--muted);margin:0 0 8px;}
.ramp span.b{width:20px;height:9px;display:block;}

.crumb{display:flex;align-items:center;gap:8px;margin:0 0 8px;font-size:11.5px;color:var(--ink-2);}
.back{background:var(--page);border:1px solid var(--card-edge);color:var(--ink-2);
  border-radius:7px;padding:3px 9px;font:500 11px "IBM Plex Sans",system-ui;cursor:pointer;}
.back:hover{color:var(--ink);}

#tip{position:fixed;pointer-events:none;opacity:0;transition:opacity .1s;background:var(--card);
  border:1px solid var(--axis);border-radius:8px;padding:8px 10px;font-size:11.5px;color:var(--ink);
  box-shadow:0 6px 20px rgba(0,0,0,.18);z-index:60;max-width:250px;line-height:1.45;}
#tip b{display:block;margin-bottom:3px;font-weight:600;}
#tip i{font-style:normal;color:var(--ink-2);display:block;}

table{border-collapse:collapse;width:100%;font-size:11.5px;}
th{text-align:left;color:var(--muted);font-weight:600;font-size:10px;padding:4px 8px 4px 0;
  border-bottom:1px solid var(--axis);text-transform:uppercase;letter-spacing:.04em;}
td{padding:5px 8px 5px 0;border-bottom:1px solid var(--grid);color:var(--ink-2);}
td:first-child{color:var(--ink);}
td.n{text-align:right;font-variant-numeric:tabular-nums;font-family:"IBM Plex Mono",monospace;}
details.tv{margin-top:9px;}
details.tv summary{cursor:pointer;font-size:11px;color:var(--muted);}
details.tv summary:hover{color:var(--ink-2);}

@media (max-width:1180px){
  .shell{grid-template-columns:minmax(0,1fr);}
  .rail{position:static;min-height:0;flex-direction:row;flex-wrap:wrap;align-items:center;}
  .brand{padding:0 12px 0 6px;}
  .railfoot{display:none;}
  .frail{position:static;}
  .g-3,.g-2{grid-template-columns:minmax(0,1fr);}
  .kpis{grid-template-columns:repeat(auto-fit,minmax(150px,1fr));}
}
@media (prefers-reduced-motion:reduce){*{transition:none!important;}}
</style>
</head>
<body>
<div class="shell">

  <nav class="rail" aria-label="Views">
    <div class="brand">
      <span class="mark">CH</span>
      <b>Calder Health<span>Claims 2020&ndash;2024</span></b>
    </div>
    <button class="nav" type="button" data-view="overview" aria-current="page">Overview</button>
    <button class="nav" type="button" data-view="care">Care Type Analysis</button>
    <button class="nav" type="button" data-view="plan">Plan Type Analysis</button>
    <button class="nav" type="button" data-view="conc">Concentration</button>
    <button class="nav" type="button" data-view="trend">Monthly Trends</button>
    <div class="railfoot">
      <p>Figures as billed. Eleven of the twenty largest conditions carry a documented
      pricing gap &mdash; rankings and shares hold, absolute dollars do not.</p>
    </div>
  </nav>

  <main>
    <div class="head">
      <div>
        <h1 id="vTitle">Overview</h1>
        <p id="vSub">Where five years of spend went, and who carried it.</p>
      </div>
      <button class="tog" id="themeBtn" type="button">Dark</button>
    </div>
    <div class="kpis" id="kpis"></div>
    <div id="views"></div>
  </main>

  <aside class="frail" aria-label="Filters">
    <div class="fgrp">
      <h4>Year</h4>
      <p class="fd">KPIs, trends, plan types</p>
      <div class="chips" id="fYear"></div>
    </div>
    <div class="fgrp">
      <h4>Payer type</h4>
      <p class="fd">KPIs and plan views; switches the share metric elsewhere</p>
      <div class="chips" id="fPayer"></div>
    </div>
    <div class="fgrp">
      <h4>Care type</h4>
      <p class="fd">Care-type and concentration views</p>
      <div class="chips" id="fCare"></div>
    </div>
    <button class="reset" id="resetBtn" type="button">Reset filters</button>
  </aside>
</div>
<div id="tip" role="status" aria-live="polite"></div>

<script>
const DATA = __DATA__;

/* ---------------- format ---------------- */
const money=v=>{const a=Math.abs(v);
  if(a>=1e9)return '$'+(v/1e9).toFixed(a>=1e10?1:2)+'B';
  if(a>=1e6)return '$'+(v/1e6).toFixed(a>=1e7?0:1)+'M';
  if(a>=1e3)return '$'+(v/1e3).toFixed(0)+'K';
  return '$'+Math.round(v);};
const money0=v=>'$'+Math.round(v).toLocaleString('en-US');
const num=v=>Math.round(v).toLocaleString('en-US');
const pct=v=>(v==null?'n/a':v.toFixed(1)+'%');
const esc=s=>String(s).replace(/[&<>"]/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;'}[c]));
const NS='http://www.w3.org/2000/svg';

/* Six bins on one teal hue. Magnitude gets a ramp; identity never does. */
const BINS=[{max:10,c:'var(--t1)',l:'<10%'},{max:15,c:'var(--t2)',l:'10-15%'},
 {max:20,c:'var(--t3)',l:'15-20%'},{max:25,c:'var(--t4)',l:'20-25%'},
 {max:30,c:'var(--t5)',l:'25-30%'},{max:1e9,c:'var(--t6)',l:'30%+'}];
const binOf=s=>(BINS.find(b=>(s==null?0:s)<b.max)||BINS[5]).c;
const rampBar=t=>'<span>'+t+'</span>'+BINS.map(b=>'<span class="b" style="background:'+b.c+'" title="'+b.l+'"></span>').join('')+'<span>&lt;10% &rarr; 30%+</span>';

/* ---------------- svg helpers ---------------- */
function svg(w,h,label){const s=document.createElementNS(NS,'svg');
  s.setAttribute('viewBox','0 0 '+w+' '+h);s.setAttribute('width',w);s.setAttribute('height',h);
  s.setAttribute('role','img');s.setAttribute('aria-label',label);return s;}
function el(t,a,p){const n=document.createElementNS(NS,t);
  for(const k in a)n.setAttribute(k,a[k]);if(p)p.appendChild(n);return n;}
function tx(p,x,y,str,cls,anchor){const t=el('text',{x:x,y:y,class:cls||'tick'},p);
  if(anchor)t.setAttribute('text-anchor',anchor);t.textContent=str;return t;}
function niceMax(v){if(v<=0)return 1;const m=Math.pow(10,Math.floor(Math.log10(v)));
  return Math.ceil(v/(m/2))*(m/2);}
/* arc path for gauge and donut; angles in radians from 12 o'clock, clockwise */
function arc(cx,cy,rOut,rIn,a0,a1){
  const p=(r,a)=>[cx+r*Math.sin(a),cy-r*Math.cos(a)];
  const big=(a1-a0)>Math.PI?1:0;
  const [x0,y0]=p(rOut,a0),[x1,y1]=p(rOut,a1),[x2,y2]=p(rIn,a1),[x3,y3]=p(rIn,a0);
  return 'M'+x0+','+y0+'A'+rOut+','+rOut+' 0 '+big+' 1 '+x1+','+y1+
         'L'+x2+','+y2+'A'+rIn+','+rIn+' 0 '+big+' 0 '+x3+','+y3+'Z';
}
const tip=document.getElementById('tip');
function hook(node,title,rows){
  const show=ev=>{tip.innerHTML='<b>'+esc(title)+'</b>'+rows.map(r=>'<i>'+esc(r)+'</i>').join('');
    tip.style.opacity='1';const pad=13,w=tip.offsetWidth,h=tip.offsetHeight;
    let x=ev.clientX+pad,y=ev.clientY+pad;
    if(x+w>innerWidth-8)x=ev.clientX-w-pad;
    if(y+h>innerHeight-8)y=ev.clientY-h-pad;
    tip.style.left=x+'px';tip.style.top=y+'px';};
  node.addEventListener('mouseenter',show);
  node.addEventListener('mousemove',show);
  node.addEventListener('mouseleave',()=>{tip.style.opacity='0';});
}
function tableOf(head,rows,textCols){const tc=new Set(textCols||[]);
  return '<table><thead><tr>'+head.map(h=>'<th>'+esc(h)+'</th>').join('')+'</tr></thead><tbody>'+
   rows.map(r=>'<tr>'+r.map((c,i)=>'<td'+(tc.has(i)?'':' class="n"')+'>'+esc(c)+'</td>').join('')+'</tr>').join('')+
   '</tbody></table>';}

/* ---------------- state ---------------- */
const YEARS=DATA.chart1.overall.map(d=>d.year);
const PAYERS=Object.keys(DATA.chart3);
const CARES=DATA.chart2.care_types.map(c=>c.care_type);
const SLOT={'Commercial':'var(--d1)','Government':'var(--d2)','Self-Pay / Uninsured':'var(--d3)'};
const state={view:'overview',years:new Set(YEARS),payers:new Set(PAYERS),
  cares:new Set(CARES),drill:null};

function shareMode(){
  if(state.payers.size!==1)return{key:'member_share',label:'all payers'};
  const o=[...state.payers][0];
  if(o==='Commercial')return{key:'share_commercial',label:'commercial members'};
  if(o==='Government')return{key:'share_government',label:'government members'};
  return{key:'member_share',label:'all payers (no per-care-type column for Self-Pay)'};
}
function yearRows(){
  const single=state.payers.size===1?[...state.payers][0]:null;
  const src=single?DATA.chart1.by_payer[single]:DATA.chart1.overall;
  return{rows:src.filter(d=>state.years.has(d.year)),single:single};
}

/* ---------------- KPI strip ---------------- */
function kpis(){
  const {rows,single}=yearRows();
  const billed=rows.reduce((a,d)=>a+d.billed,0);
  const paid=rows.reduce((a,d)=>a+d.member_paid,0);
  const hd=DATA.chart4.headline;
  const cards=[
    [money(billed),'Total billed',rows.length+' of 5 years'+(single?' · '+single:'')],
    [money(paid),'Paid by members',pct(100*paid/billed)+' of every dollar'],
    [num(hd.Patients.population),'Members','across '+num(hd.Organisations.population)+' facilities'],
    [num(hd.Organisations.count_for_half),'Facilities = half of spend',hd.Organisations.pct_for_half.toFixed(2)+'% of the network'],
    [num(hd.Patients.count_for_half),'Members = half of spend',hd.Patients.pct_for_half.toFixed(2)+'% of members']
  ];
  document.getElementById('kpis').innerHTML=cards.map(c=>
    '<div class="kpi"><div class="kpi-v">'+esc(c[0])+'</div><div class="kpi-k">'+esc(c[1])+
    '</div><div class="kpi-n">'+esc(c[2])+'</div></div>').join('');
}

/* ---------------- gauge: one bounded percentage ---------------- */
function gauge(host,value,label){
  const W=250,H=160,cx=125,cy=128,rO=96,rI=68;
  const s=svg(W,H,label+': '+pct(value));
  const A0=-Math.PI/2,A1=Math.PI/2;
  el('path',{d:arc(cx,cy,rO,rI,A0,A1),fill:'var(--grid)'},s);
  const a=A0+(A1-A0)*Math.min(1,value/100);
  el('path',{d:arc(cx,cy,rO,rI,A0,a),fill:'var(--accent)'},s);
  const t=tx(s,cx,cy-14,pct(value),'gauge-v','middle');t.setAttribute('font-size','30');
  tx(s,cx,cy+8,label,'tick','middle');
  tx(s,cx-rO+6,cy+16,'0%','tick','middle');
  tx(s,cx+rO-6,cy+16,'100%','tick','middle');
  host.innerHTML='';host.appendChild(s);
}

/* ---------------- donut: part-to-whole, 3 segments ---------------- */
function donut(host,slices,total,label){
  const W=334,H=200,cx=100,cy=100,rO=76,rI=47;
  const s=svg(W,H,label);
  let a=0;
  slices.forEach(sl=>{
    const frac=sl.value/total, a1=a+frac*Math.PI*2;
    const p=el('path',{d:arc(cx,cy,rO,rI,a,a1),fill:sl.color,
      stroke:'var(--card)','stroke-width':2},s);
    hook(p,sl.name,[money0(sl.value),(100*frac).toFixed(1)+'% of billed']);
    a=a1;
  });
  tx(s,cx,cy-3,money(total),'vlab','middle').setAttribute('font-size','14');
  tx(s,cx,cy+12,'total billed','tick','middle');
  slices.forEach((sl,i)=>{
    const y=34+i*30;
    el('rect',{x:192,y:y-9,width:9,height:9,rx:2,fill:sl.color},s);
    tx(s,206,y,sl.short,'blab').setAttribute('font-size','11');
    tx(s,206,y+13,money(sl.value)+' · '+(100*sl.value/total).toFixed(1)+'%','vlab')
      .setAttribute('font-size','10');
  });
  host.innerHTML='';host.appendChild(s);
}

/* ---------------- horizontal bars ---------------- */
function hbars(host,rows,opt){
  opt=opt||{};
  const L=opt.gutter||146,R=opt.right||74,W=opt.width||470,rowH=opt.rowH||26;
  const maxChars=Math.floor((L-12)/6.4);
  const H=rows.length*rowH+10;
  const s=svg(W,H,opt.label||'bar chart');
  const pw=W-L-R,maxV=Math.max(...rows.map(r=>r.value));
  rows.forEach((r,i)=>{
    const y=i*rowH+5,h=rowH-11;
    const w=Math.max(2,pw*r.value/maxV);
    const g=el('g',{class:r.drill?'hit':''},s);
    if(r.drill){g.setAttribute('tabindex','0');g.setAttribute('role','button');
      g.setAttribute('aria-label','Drill into '+r.name);
      const go=()=>{state.drill=r.name;render();};
      g.onclick=go;g.onkeydown=e=>{if(e.key==='Enter'||e.key===' '){e.preventDefault();go();}};}
    el('rect',{x:L,y:y,width:w,height:h,rx:3,fill:r.color||'var(--accent)'},g);
    const nm=r.name.length>maxChars?r.name.slice(0,maxChars-1)+'…':r.name;
    tx(g,L-8,y+h/2+4,nm,'blab','end');
    tx(g,L+w+7,y+h/2+4,r.right,'vlab');
    hook(g,r.name,r.tip||[]);
  });
  el('line',{x1:L,y1:2,x2:L,y2:rows.length*rowH+4,class:'axisline'},s);
  host.innerHTML='';host.appendChild(s);
}

/* ---------------- grouped columns ---------------- */
function groupCols(host,rows,series,label){
  const W=Math.max(360,rows.length*96+70),H=222,L=58,R=12,TOP=14,ph=H-TOP-40;
  const s=svg(W,H,label);
  const maxV=niceMax(Math.max(...rows.map(r=>Math.max(...series.map(k=>r[k.key])))));
  for(let i=0;i<=4;i++){const y=TOP+ph-ph*i/4;
    el('line',{x1:L,y1:y,x2:W-R,y2:y,class:'gridline'},s);
    tx(s,L-7,y+4,money(maxV*i/4),'tick','end');}
  const pw=W-L-R,gw=pw/rows.length,bw=Math.min(26,(gw-14)/series.length);
  rows.forEach((r,i)=>{
    const gx=L+gw*i+gw/2;
    series.forEach((k,j)=>{
      const h=ph*r[k.key]/maxV;
      const x=gx-(series.length*bw)/2+j*bw;
      const rect=el('rect',{x:x,y:TOP+ph-h,width:bw-2,height:h,rx:3,fill:k.color},s);
      hook(rect,r.label+' · '+k.name,[money0(r[k.key])]);
    });
    tx(s,gx,TOP+ph+17,r.label,'tick','middle');
  });
  el('line',{x1:L,y1:TOP+ph,x2:W-R,y2:TOP+ph,class:'axisline'},s);
  host.innerHTML='';host.appendChild(s);
}

/* ---------------- monthly line: 60 points on a shared axis ---------------- */
function monthLine(host,pts,opt){
  const W=opt.width||660,H=opt.height||230,L=58,R=16,TOP=14,ph=H-TOP-40,pw=W-L-R;
  const s=svg(W,H,opt.label||'monthly trend');
  const maxV=niceMax(Math.max(...pts.map(p=>p.v)));
  for(let i=0;i<=4;i++){const y=TOP+ph-ph*i/4;
    el('line',{x1:L,y1:y,x2:W-R,y2:y,class:'gridline'},s);
    tx(s,L-7,y+4,opt.fmt?opt.fmt(maxV*i/4):money(maxV*i/4),'tick','end');}
  const X=i=>L+pw*(i+0.5)/pts.length, Y=v=>TOP+ph-ph*v/maxV;
  /* one January tick per year rather than 60 unreadable month labels */
  pts.forEach((p,i)=>{
    if(!p.month.endsWith('-01'))return;
    const x=X(i);
    el('line',{x1:x,y1:TOP,x2:x,y2:TOP+ph,class:'gridline'},s);
    tx(s,x,TOP+ph+17,p.month.slice(0,4),'tick','middle');});
  el('path',{d:'M'+pts.map((p,i)=>X(i)+','+Y(p.v)).join('L'),fill:'none',
    stroke:opt.color||'var(--accent)','stroke-width':2,'stroke-linejoin':'round'},s);
  el('line',{x1:L,y1:TOP+ph,x2:W-R,y2:TOP+ph,class:'axisline'},s);
  /* one hover band across the plot, snapping to the nearest month */
  const hit=el('rect',{x:L,y:TOP,width:pw,height:ph,fill:'transparent'},s);
  const rule=el('line',{x1:-9,y1:TOP,x2:-9,y2:TOP+ph,stroke:'var(--axis)','stroke-width':1},s);
  const dot=el('circle',{cx:-20,cy:-20,r:5,fill:opt.color||'var(--accent)',
    stroke:'var(--card)','stroke-width':2},s);
  hit.addEventListener('mousemove',ev=>{
    const r=hit.getBoundingClientRect();
    let i=Math.round(((ev.clientX-r.left)/r.width)*pts.length-0.5);
    i=Math.max(0,Math.min(pts.length-1,i));
    const p=pts[i];
    rule.setAttribute('x1',X(i));rule.setAttribute('x2',X(i));
    dot.setAttribute('cx',X(i));dot.setAttribute('cy',Y(p.v));
    tip.innerHTML='<b>'+esc(p.month)+'</b>'+(p.rows||[]).map(t=>'<i>'+esc(t)+'</i>').join('');
    tip.style.opacity='1';
    let x=ev.clientX+13;if(x+tip.offsetWidth>innerWidth-8)x=ev.clientX-tip.offsetWidth-13;
    tip.style.left=x+'px';tip.style.top=(ev.clientY+13)+'px';});
  hit.addEventListener('mouseleave',()=>{tip.style.opacity='0';
    dot.setAttribute('cx',-20);rule.setAttribute('x1',-9);rule.setAttribute('x2',-9);});
  host.innerHTML='';host.appendChild(s);
}

/* ---------------- multi-line ---------------- */
function lines(host,yrs,seriesList,label){
  const W=Math.max(400,yrs.length*84+150),H=232,L=48,R=104,TOP=14,ph=H-TOP-36;
  const s=svg(W,H,label);
  const pw=W-L-R;
  for(let i=0;i<=4;i++){const y=TOP+ph-ph*i/4;
    el('line',{x1:L,y1:y,x2:W-R,y2:y,class:'gridline'},s);
    tx(s,L-7,y+4,(i*25)+'%','tick','end');}
  el('line',{x1:L,y1:TOP+ph,x2:W-R,y2:TOP+ph,class:'axisline'},s);
  yrs.forEach((y,i)=>tx(s,L+pw*(i+0.5)/yrs.length,TOP+ph+17,y,'tick','middle'));
  seriesList.forEach(ser=>{
    const pts=ser.points.map((d,i)=>({x:L+pw*(i+0.5)/yrs.length,
      y:TOP+ph-ph*d.v/100,d:d}));
    if(pts.length>1)el('path',{d:'M'+pts.map(p=>p.x+','+p.y).join('L'),fill:'none',
      stroke:ser.color,'stroke-width':2,'stroke-linejoin':'round'},s);
    pts.forEach(p=>{const c=el('circle',{cx:p.x,cy:p.y,r:4.5,fill:ser.color,
      stroke:'var(--card)','stroke-width':2},s);
      hook(c,ser.name+' · '+p.d.year,[pct(p.d.v)].concat(p.d.extra||[]));});
    const last=pts[pts.length-1];
    if(last)tx(s,last.x+9,last.y+4,ser.short+' '+pct(last.d.v),'vlab');
  });
  host.innerHTML='';host.appendChild(s);
}

/* ================= VIEWS ================= */
const VIEWS={};

VIEWS.overview=()=>{
  const {rows,single}=yearRows();
  const billed=rows.reduce((a,d)=>a+d.billed,0);
  const paid=rows.reduce((a,d)=>a+d.member_paid,0);
  const sm=shareMode();
  const care=DATA.chart2.care_types.filter(c=>state.cares.has(c.care_type))
    .slice().sort((a,b)=>b[sm.key]-a[sm.key]).slice(0,6);

  const payerSlices=PAYERS.filter(p=>state.payers.has(p)).map(p=>{
    const v=DATA.chart1.by_payer[p].filter(d=>state.years.has(d.year))
      .reduce((a,d)=>a+d.billed,0);
    return{name:p,short:p.replace(' / Uninsured',''),value:v,color:SLOT[p]};
  }).sort((a,b)=>b.value-a.value);
  const payerTotal=payerSlices.reduce((a,s)=>a+s.value,0);

  return {
    html:'<div class="grid g-3">'+
      '<div class="card"><h3>Member-paid share</h3><p class="cq">Of every dollar paid, how much came from members</p><div id="oGauge"></div>'+
      '<p class="cnote">Bounded 0&ndash;100%, so a gauge is honest here. '+money(paid)+' of '+money(billed)+'.</p></div>'+
      '<div class="card"><h3>Billed by plan type</h3><p class="cq">Where the spend sits across the two lines of business</p><div id="oDonut"></div></div>'+
      '<div class="card"><h3>Heaviest member burden</h3><p class="cq">Care types by share of the bill members carry</p>'+
      '<div class="applied">share for '+esc(sm.label)+'</div><div id="oBars"></div></div>'+
      '</div>'+
      '<div class="grid g-2" style="margin-top:12px;">'+
      '<div class="card"><h3>Billed against member-paid, by year</h3><p class="cq">Two measures, one scale &mdash; both are dollars</p>'+
      '<div class="legend"><span class="lk"><span class="sw" style="background:var(--d1)"></span>Total billed</span>'+
      '<span class="lk"><span class="sw" style="background:var(--d2)"></span>Paid by members</span></div>'+
      '<div class="scrollx"><div id="oCols"></div></div></div>'+
      '<div class="card"><h3>Facility concentration</h3><p class="cq">Cumulative share of spend, largest facilities first</p>'+
      '<div class="scrollx"><div id="oConc"></div></div>'+
      '<p class="cnote">86 of 3,918 facilities carry half of all spend &mdash; 2.2% of the network.</p></div>'+
      '</div>',
    draw(){
      gauge(document.getElementById('oGauge'),100*paid/billed,'of every dollar');
      donut(document.getElementById('oDonut'),payerSlices,payerTotal,'Billed by plan type');
      hbars(document.getElementById('oBars'),care.map(c=>({
        name:c.care_type,value:c[sm.key],color:binOf(c[sm.key]),
        right:pct(c[sm.key]),
        tip:['Member share: '+pct(c[sm.key]),'Total billed: '+money0(c.billed),
             'People affected: '+num(c.members)]})),
        {label:'Care types by member-paid share',width:452,gutter:132,right:50,rowH:27});
      groupCols(document.getElementById('oCols'),rows.map(d=>({
        label:d.year,billed:d.billed,paid:d.member_paid})),
        [{key:'billed',name:'Total billed',color:'var(--d1)'},
         {key:'paid',name:'Paid by members',color:'var(--d2)'}],
        'Billed and member-paid by year');
      hbars(document.getElementById('oConc'),DATA.chart4.facilities.slice(0,8).map((f,i)=>({
        name:(i+1)+'. '+f.name,value:f.cumulative_pct,color:'var(--t4)',
        right:f.cumulative_pct.toFixed(1)+'%',
        tip:['Own billed: '+money0(f.billed),'Cumulative: '+f.cumulative_pct.toFixed(2)+'%']})),
        {label:'Facility cumulative share',width:430,gutter:180,right:46});
    }};
};

VIEWS.care=()=>{
  const sm=shareMode();
  const drilled=state.drill;
  let rows,unit;
  if(drilled){
    unit='condition';
    rows=DATA.chart2.conditions.filter(c=>c.care_type===drilled)
      .map(c=>({name:c.condition,billed:c.billed,share:c.member_share,
        members:c.members,paid:c.member_paid}));
  }else{
    unit='care type';
    rows=DATA.chart2.care_types.filter(c=>state.cares.has(c.care_type))
      .map(c=>({name:c.care_type,billed:c.billed,share:c[sm.key],
        members:c.members,paid:c.member_paid,drill:true}));
  }
  rows.sort((a,b)=>b.billed-a.billed);
  rows=rows.slice(0,20);

  return{
    html:'<div class="card">'+
      '<h3>Spend by '+unit+'</h3><p class="cq">Bar length is total billed; colour is the share members carry</p>'+
      '<div class="applied">'+(drilled?'conditions within '+esc(drilled):esc(String(state.cares.size))+' of '+CARES.length+' care types')+
      ' &middot; share for '+esc(sm.label)+'</div>'+
      '<div class="crumb" id="cCrumb"></div>'+
      '<div class="ramp" id="cRamp"></div>'+
      '<div class="scrollx"><div id="cBars"></div></div>'+
      '<details class="tv"><summary>Table view</summary><div id="cTable"></div></details>'+
      '</div>',
    draw(){
      const cr=document.getElementById('cCrumb');cr.innerHTML='';
      if(drilled){
        const b=document.createElement('button');b.type='button';b.className='back';
        b.textContent='← All care types';b.onclick=()=>{state.drill=null;render();};
        cr.appendChild(b);
        const sp=document.createElement('span');
        sp.innerHTML='<strong>'+esc(drilled)+'</strong> · '+rows.length+' condition'+(rows.length===1?'':'s');
        cr.appendChild(sp);
      }else{
        cr.innerHTML='<span style="font-style:italic;color:var(--muted)">Click any bar to open the conditions inside it.</span>';
      }
      document.getElementById('cRamp').innerHTML=rampBar('Member-paid share');
      hbars(document.getElementById('cBars'),rows.map(r=>({
        name:r.name,value:r.billed,color:binOf(r.share),drill:r.drill,
        right:money(r.billed)+' · '+pct(r.share),
        tip:['Total billed: '+money0(r.billed),'Member share: '+pct(r.share),
             'Paid by members: '+money0(r.paid),'People affected: '+num(r.members),
             r.drill?'Click to drill in':''].filter(Boolean)})),
        {label:'Billed by '+unit,width:700,gutter:210,right:118,rowH:27});
      document.getElementById('cTable').innerHTML=tableOf(
        [drilled?'Condition':'Care type','Total billed','Member share','Paid by members','People'],
        rows.map(r=>[r.name,money0(r.billed),pct(r.share),money0(r.paid),num(r.members)]),[0]);
    }};
};

VIEWS.plan=()=>{
  const yrs=YEARS.filter(y=>state.years.has(y));
  const shown=PAYERS.filter(p=>state.payers.has(p));
  const care=DATA.chart2.care_types.filter(c=>state.cares.has(c.care_type))
    .slice().sort((a,b)=>(b.share_commercial-b.share_government)-(a.share_commercial-a.share_government))
    .slice(0,8);
  return{
    html:'<div class="grid g-2">'+
      '<div class="card"><h3>Member-paid share over time</h3><p class="cq">Does the plan a member holds change what they pay?</p>'+
      '<div class="legend">'+shown.map(p=>'<span class="lk"><span class="sw" style="background:'+SLOT[p]+'"></span>'+esc(p)+'</span>').join('')+'</div>'+
      '<div class="scrollx"><div id="pLines"></div></div>'+
      '<p class="cnote">Self-pay sits at 100% by definition &mdash; there is no insurer to carry any of it.</p></div>'+
      '<div class="card"><h3>Commercial against government</h3><p class="cq">Same care type, the two benefit designs side by side</p>'+
      '<div class="legend"><span class="lk"><span class="sw" style="background:var(--d1)"></span>Commercial</span>'+
      '<span class="lk"><span class="sw" style="background:var(--d2)"></span>Government</span></div>'+
      '<div class="scrollx"><div id="pGap"></div></div>'+
      '<p class="cnote">Ordered by the size of the gap. This is the one finding price correction leaves exactly unchanged.</p></div>'+
      '</div>',
    draw(){
      lines(document.getElementById('pLines'),yrs,shown.map(p=>({
        name:p,short:p.replace(' / Uninsured',''),color:SLOT[p],
        points:DATA.chart3[p].filter(d=>state.years.has(d.year)).map(d=>({
          year:d.year,v:d.member_share,
          extra:['Paid per member: '+money0(d.member_paid_per_member)]}))})),
        'Member-paid share by plan type');
      /* dumbbell: two dots and the gap between them, one row per care type */
      const W=430,L=150,R=54,rowH=27,H=care.length*rowH+12;
      const s=svg(W,H,'Commercial against government member share by care type');
      const pw=W-L-R;
      care.forEach((c,i)=>{
        const y=i*rowH+rowH/2;
        const xc=L+pw*Math.min(100,c.share_commercial)/100;
        const xg=L+pw*Math.min(100,c.share_government)/100;
        el('line',{x1:xg,y1:y,x2:xc,y2:y,stroke:'var(--axis)','stroke-width':2},s);
        const g=el('g',{},s);
        el('circle',{cx:xg,cy:y,r:5,fill:'var(--d2)',stroke:'var(--card)','stroke-width':1.5},g);
        el('circle',{cx:xc,cy:y,r:5,fill:'var(--d1)',stroke:'var(--card)','stroke-width':1.5},g);
        const nm=c.care_type.length>21?c.care_type.slice(0,20)+'…':c.care_type;
        tx(g,L-8,y+4,nm,'blab','end');
        tx(g,L+pw+7,y+4,'+'+Math.round(c.share_commercial-c.share_government)+' pts','vlab');
        hook(g,c.care_type,['Commercial: '+pct(c.share_commercial),
          'Government: '+pct(c.share_government),
          'Gap: '+(c.share_commercial-c.share_government).toFixed(1)+' points']);
      });
      [0,50,100].forEach(v=>{const x=L+pw*v/100;
        el('line',{x1:x,y1:4,x2:x,y2:care.length*rowH,class:'goalline'},s);});
      const host=document.getElementById('pGap');host.innerHTML='';host.appendChild(s);
    }};
};

VIEWS.conc=()=>{
  const hd=DATA.chart4.headline;
  const sel=DATA.chart2.care_types.filter(c=>state.cares.has(c.care_type))
    .slice().sort((a,b)=>b.billed-a.billed);
  const tot=sel.reduce((a,c)=>a+c.billed,0);
  let run=0;
  const careRows=sel.map(c=>{run+=c.billed;
    return{name:c.care_type,billed:c.billed,cum:100*run/tot};});
  const half=careRows.findIndex(r=>r.cum>=50)+1;
  return{
    html:'<div class="grid g-2">'+
      '<div class="card"><h3>By care type</h3><p class="cq">'+half+' of '+careRows.length+' care types reach half of the selected spend</p>'+
      '<div class="scrollx"><div id="kCare"></div></div></div>'+
      '<div class="card"><h3>By facility &mdash; top 12 of 3,918</h3><p class="cq">'+
      num(hd.Organisations.count_for_half)+' facilities ('+hd.Organisations.pct_for_half.toFixed(2)+'%) carry half of all spend</p>'+
      '<div class="scrollx"><div id="kFac"></div></div></div>'+
      '</div>'+
      '<div class="card" style="margin-top:12px;"><h3>By member</h3>'+
      '<p class="cq">It takes '+num(hd.Patients.count_for_half)+' members ('+hd.Patients.pct_for_half.toFixed(2)+
      '%) to reach the same half. The priciest 1% carry '+hd.Patients.top1+'%.</p>'+
      '<p class="sub">Drawn as a curve rather than ranked bars: at 100 ranks the shape is the finding, and 100 bars would hide it. The dashed diagonal is perfectly even spending.</p>'+
      '<div class="scrollx"><div id="kMem"></div></div></div>',
    draw(){
      hbars(document.getElementById('kCare'),careRows.map((r,i)=>({
        name:(i+1)+'. '+r.name,value:r.cum,color:'var(--t4)',right:r.cum.toFixed(1)+'%',
        tip:['Own billed: '+money0(r.billed),'Cumulative: '+r.cum.toFixed(2)+'%']})),
        {label:'Cumulative share by care type',width:470,gutter:190,right:50});
      hbars(document.getElementById('kFac'),DATA.chart4.facilities.slice(0,12).map((f,i)=>({
        name:(i+1)+'. '+f.name,value:f.cumulative_pct,color:'var(--t4)',
        right:f.cumulative_pct.toFixed(1)+'%',
        tip:['Own billed: '+money0(f.billed),'Members: '+num(f.members),
             'Cumulative: '+f.cumulative_pct.toFixed(2)+'%']})),
        {label:'Cumulative share by facility',width:470,gutter:210,right:50});
      /* Lorenz */
      const W=640,H=270,L=48,R=16,TOP=12,ph=H-TOP-40,pw=W-L-R;
      const s=svg(W,H,'Cumulative share of spend against share of members');
      for(let i=0;i<=4;i++){const y=TOP+ph-ph*i/4;
        el('line',{x1:L,y1:y,x2:W-R,y2:y,class:'gridline'},s);
        tx(s,L-7,y+4,(i*25)+'%','tick','end');}
      el('line',{x1:L,y1:TOP+ph,x2:W-R,y2:TOP,class:'goalline'},s);
      tx(s,L+pw*0.56,TOP+ph-ph*0.56+15,'perfectly even','tick','middle');
      const pts=DATA.chart4.members.map(m=>[L+pw*m.pct_group/100,TOP+ph-ph*m.cumulative_pct/100]);
      el('path',{d:'M'+pts.map(p=>p[0]+','+p[1]).join('L'),fill:'none',
        stroke:'var(--accent)','stroke-width':2.5,'stroke-linejoin':'round'},s);
      const hit=el('rect',{x:L,y:TOP,width:pw,height:ph,fill:'transparent'},s);
      const dot=el('circle',{cx:-20,cy:-20,r:5,fill:'var(--accent)',
        stroke:'var(--card)','stroke-width':2},s);
      hit.addEventListener('mousemove',ev=>{
        const r=hit.getBoundingClientRect();
        const frac=(ev.clientX-r.left)/r.width*100;
        let best=DATA.chart4.members[0];
        DATA.chart4.members.forEach(m=>{
          if(Math.abs(m.pct_group-frac)<Math.abs(best.pct_group-frac))best=m;});
        dot.setAttribute('cx',L+pw*best.pct_group/100);
        dot.setAttribute('cy',TOP+ph-ph*best.cumulative_pct/100);
        tip.innerHTML='<b>Priciest '+best.pct_group+'% of members</b><i>carry '+
          best.cumulative_pct.toFixed(1)+'% of all spend</i>';
        tip.style.opacity='1';
        let x=ev.clientX+13;if(x+tip.offsetWidth>innerWidth-8)x=ev.clientX-tip.offsetWidth-13;
        tip.style.left=x+'px';tip.style.top=(ev.clientY+13)+'px';});
      hit.addEventListener('mouseleave',()=>{tip.style.opacity='0';dot.setAttribute('cx',-20);});
      el('line',{x1:L,y1:TOP+ph,x2:W-R,y2:TOP+ph,class:'axisline'},s);
      [0,25,50,75,100].forEach(v=>tx(s,L+pw*v/100,TOP+ph+17,v+'%','tick','middle'));
      tx(s,L+pw/2,H-5,'Share of members, priciest first','tick','middle');
      const host=document.getElementById('kMem');host.innerHTML='';host.appendChild(s);
    }};
};

VIEWS.trend=()=>{
  const {rows,single}=yearRows();
  const M=DATA.monthly;

  /* Monthly needs q4_monthly_trends.sql to have been run. Without it the
     saved results are yearly only, and inventing a month axis from five
     annual points would be fabrication, so the view says so instead. */
  if(!M||!M.overall||!M.overall.length){
    return{
      html:'<div class="card"><h3>Monthly data has not been generated yet</h3>'+
        '<p class="cq">This view needs one query run against the warehouse</p>'+
        '<p class="sub">Every saved result in <code>sql/results/</code> is aggregated to the year, '+
        'so there are five points available, not sixty. Run '+
        '<code>sql/analysis/q4_monthly_trends.sql</code> against '+
        '<code>V_CLAIMS_TX_WITH_CARETYPE</code> and save the output to '+
        '<code>sql/results/q4_monthly_trends_2020_2024.csv</code>, then rebuild. '+
        'Drawing a month axis from annual figures would invent the shape between the points.</p>'+
        '<h3 style="margin-top:14px;">Yearly, in the meantime</h3>'+
        '<div class="scrollx"><div id="tBilled"></div></div>'+
        '<div id="tTable" style="margin-top:12px;"></div></div>',
      draw(){
        groupCols(document.getElementById('tBilled'),rows.map(d=>({
          label:d.year,billed:d.billed})),
          [{key:'billed',name:'Total billed',color:'var(--d1)'}],'Total billed by year');
        document.getElementById('tTable').innerHTML=tableOf(
          ['Year','Total billed','Members','Cost per member','Paid by members','Member share'],
          rows.map(d=>[d.year,money0(d.billed),num(d.members),money0(d.billed_per_member),
            money0(d.member_paid),pct(d.member_share)]),[0]);
      }};
  }

  /* filter months by the selected years; pick the payer series if exactly one */
  const src=(single&&M.by_payer[single])?M.by_payer[single]:M.overall;
  const pts=src.filter(p=>state.years.has(p.year));
  const careSel=[...state.cares];
  const oneCare=careSel.length===1?careSel[0]:null;
  const carePts=(oneCare&&M.by_care[oneCare])
    ? M.by_care[oneCare].filter(p=>state.years.has(p.year)) : null;

  const peak=pts.reduce((a,p)=>p.billed>a.billed?p:a,pts[0]);
  const low=pts.reduce((a,p)=>p.billed<a.billed?p:a,pts[0]);

  return{
    html:'<div class="grid g-2">'+
      '<div class="card"><h3>Total billed by month</h3>'+
      '<p class="cq">'+pts.length+' months'+(single?' · '+esc(single):'')+'</p>'+
      '<div class="applied">peak '+esc(peak.month)+' at '+money(peak.billed)+
      ' · lowest '+esc(low.month)+' at '+money(low.billed)+'</div>'+
      '<div class="scrollx"><div id="mBilled"></div></div></div>'+
      '<div class="card"><h3>Member-paid share by month</h3>'+
      '<p class="cq">The share of each month\'s bill that members carried</p>'+
      '<div class="scrollx"><div id="mShare"></div></div>'+
      '<p class="cnote">Plotted on its own panel rather than sharing an axis with dollars '+
      '&mdash; a percentage and a dollar total are different units.</p></div>'+
      '</div>'+
      (carePts?'<div class="card" style="margin-top:12px;"><h3>'+esc(oneCare)+' by month</h3>'+
        '<p class="cq">Billed within the one selected care type</p>'+
        '<div class="scrollx"><div id="mCare"></div></div></div>'
       :'<div class="card" style="margin-top:12px;"><h3>By care type</h3>'+
        '<p class="cq">Select a single care type in the filter rail to chart it by month</p>'+
        '<p class="cnote">'+state.cares.size+' care types are selected. The monthly file carries '+
        'a series per care type; charting all of them at once would put '+state.cares.size+
        ' lines on one plot, well past the point where any of them can be told apart.</p></div>')+
      '<div class="card" style="margin-top:12px;"><h3>Month by month</h3>'+
      '<p class="cq">Every figure behind the panels above</p>'+
      '<details class="tv" open><summary>Table view</summary><div id="mTable"></div></details></div>',
    draw(){
      monthLine(document.getElementById('mBilled'),pts.map(p=>({
        month:p.month,v:p.billed,
        rows:['Billed: '+money0(p.billed),'Paid by members: '+money0(p.member_paid),
              'Members: '+num(p.members)]})),
        {label:'Total billed by month',color:'var(--d1)',width:620});
      monthLine(document.getElementById('mShare'),pts.map(p=>({
        month:p.month,v:p.member_share,
        rows:['Member share: '+pct(p.member_share),
              'Paid by members: '+money0(p.member_paid)]})),
        {label:'Member-paid share by month',color:'var(--d2)',width:620,
         fmt:v=>v.toFixed(0)+'%'});
      if(carePts)monthLine(document.getElementById('mCare'),carePts.map(p=>({
        month:p.month,v:p.billed,
        rows:['Billed: '+money0(p.billed),'Member share: '+pct(p.member_share),
              'People affected: '+num(p.members)]})),
        {label:oneCare+' billed by month',color:'var(--t5)',width:1000});
      document.getElementById('mTable').innerHTML=tableOf(
        ['Month','Total billed','Paid by members','Member share','People affected','Billed per person'],
        pts.map(p=>[p.month,money0(p.billed),money0(p.member_paid),pct(p.member_share),
          num(p.members),money0(p.billed_per_member)]),[0]);
    }};
};

const TITLES={
  overview:['Overview','Where five years of spend went, and who carried it.'],
  care:['Care Type Analysis','Spend and member burden by care type, drillable to condition.'],
  plan:['Plan Type Analysis','What a member pays depends on the plan they hold.'],
  conc:['Concentration','How few care types, facilities or members reach half of spend.'],
  trend:['Monthly Trends','Billed and member burden month by month across the window.']
};

/* ---------------- wiring ---------------- */
function chips(host,values,sel,onToggle,labelFn){
  host.innerHTML='';
  values.forEach(v=>{
    const b=document.createElement('button');
    b.type='button';b.className='chip';b.textContent=labelFn?labelFn(v):v;
    b.setAttribute('aria-pressed',sel.has(v)?'true':'false');
    b.onclick=()=>{onToggle(v);render();};
    host.appendChild(b);});
}
function toggle(set,v,all){
  if(set.has(v)){if(set.size>1)set.delete(v);}else set.add(v);
  if(set.size===0)all.forEach(x=>set.add(x));
}
function render(){
  chips(document.getElementById('fYear'),YEARS,state.years,v=>toggle(state.years,v,YEARS));
  chips(document.getElementById('fPayer'),PAYERS,state.payers,
    v=>toggle(state.payers,v,PAYERS),p=>p.replace(' / Uninsured',''));
  chips(document.getElementById('fCare'),CARES,state.cares,v=>toggle(state.cares,v,CARES),
    c=>c.length>17?c.slice(0,16)+'…':c);
  document.querySelectorAll('.nav').forEach(n=>{
    if(n.dataset.view===state.view)n.setAttribute('aria-current','page');
    else n.removeAttribute('aria-current');});
  document.getElementById('vTitle').textContent=TITLES[state.view][0];
  document.getElementById('vSub').textContent=TITLES[state.view][1];
  kpis();
  const v=VIEWS[state.view]();
  document.getElementById('views').innerHTML=v.html;
  v.draw();
}
document.querySelectorAll('.nav').forEach(n=>{
  n.onclick=()=>{state.view=n.dataset.view;if(n.dataset.view!=='care')state.drill=null;render();};});
document.getElementById('resetBtn').onclick=()=>{
  state.years=new Set(YEARS);state.payers=new Set(PAYERS);
  state.cares=new Set(CARES);state.drill=null;render();};

const themeBtn=document.getElementById('themeBtn');
function applyTheme(d){
  document.documentElement.setAttribute('data-theme',d?'dark':'light');
  themeBtn.textContent=d?'Light':'Dark';
  try{localStorage.setItem('cbi-theme',d?'dark':'light');}catch(e){}
  render();
}
const stamped=document.documentElement.getAttribute('data-theme');
let dark=stamped?stamped==='dark':matchMedia('(prefers-color-scheme: dark)').matches;
try{const s=localStorage.getItem('cbi-theme');if(!stamped&&s)dark=s==='dark';}catch(e){}
applyTheme(dark);
themeBtn.onclick=()=>{dark=!dark;applyTheme(dark);};
</script>
</body>
</html>
'''


def build():
    with open(DATA) as fh:
        payload = fh.read()
    return PAGE.replace('__DATA__', payload)


def build_artifact(page):
    """Artifacts are wrapped in their own doctype/head/body at publish time."""
    drop = ['<!doctype html>', '<html lang="en">', '<head>', '</head>',
            '<body>', '</body>', '</html>',
            '<meta charset="utf-8">',
            '<meta name="viewport" content="width=device-width, initial-scale=1">']
    out = page
    for token in drop:
        out = out.replace(token + '\n', '').replace(token, '')
    return out.strip() + '\n'


if __name__ == '__main__':
    page = build()
    with open(OUT, 'w') as fh:
        fh.write(page)
    with open(ART, 'w') as fh:
        fh.write(build_artifact(page))
    print('wrote %s (%.0f KB)' % (OUT, os.path.getsize(OUT) / 1024))
    print('wrote %s (%.0f KB)' % (ART, os.path.getsize(ART) / 1024))
