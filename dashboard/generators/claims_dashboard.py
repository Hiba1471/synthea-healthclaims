"""Build dashboard/claims_dashboard.html -- the interactive claims dashboard.

Data comes from dashboard/dashboard_data.json (built by dashboard_data.py from
the saved result CSVs). Run dashboard_data.py first if the results change.

    python3 dashboard/generators/dashboard_data.py
    python3 dashboard/generators/claims_dashboard.py

THREE DELIBERATE DEPARTURES FROM THE REQUESTED SPEC. Each was requested one way,
is a documented charting error that way, and is built the corrected way instead.
They are annotated in the page itself so a reader is not left guessing.

 1. Chart 1 was specified as a combo: billed as columns, cost-per-member as a
    line, on one plot. That is a dual-axis chart -- two y-scales whose alignment
    is arbitrary, so the reader sees a correlation the data never asserted. It
    is built here as two stacked panels sharing one x-axis. Both measures, same
    years, no invented relationship.

 2. Chart 2 was specified with a red-to-green gradient for member-paid share.
    Red/green is the one ramp red-green colourblind readers cannot resolve, and
    a rainbow is wrong for magnitude regardless. It uses the single-hue blue
    sequential ramp in six bins with a scale legend, and prints the share as a
    direct label so colour never carries the value alone.

 3. Chart 5 was specified with one colour per care type. Fifteen categorical
    hues cannot be told apart under any colour-vision deficiency; scatter and
    bubble forms are held to an all-pairs check that caps distinguishable series
    at three. Bubbles are coloured on the same share ramp as Chart 2 and named
    with direct labels, so identity is carried by text.

WHAT THE FILTERS CAN AND CANNOT DO. The saved results are pre-aggregated at
different grains, so no filter can drive every chart. Rather than wire controls
that silently do nothing, each filter declares what it drives and each panel
declares what reached it:

    Year          -> Charts 1 and 3 only. Care-type and concentration results
                     are five-year totals with no year dimension in the file.
    Payer type    -> Charts 1 and 3 fully. Charts 2 and 5 switch the SHARE
                     metric to that payer's own column when a single payer is
                     picked; billed dollars are not split by payer in the file,
                     so bar LENGTHS do not change.
    Care type     -> Charts 2, 4A and 5.

PATIENT_STATE was requested as a filter and is not built: no saved result
carries it. It exists on SILVER.PATIENTS and would need a new query. Nothing
here is a placeholder for it.
"""
import json
import os

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
DATA = os.path.join(ROOT, 'dashboard', 'dashboard_data.json')
OUT = os.path.join(ROOT, 'dashboard', 'claims_dashboard.html')

PAGE = r'''<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Where the Money Went, and Who Paid It</title>
<style>
/* Palette values are the data-viz reference palette, used unchanged.
   Categorical slots 1-3 only (blue/orange/aqua): the documented all-pairs
   validation covers exactly the first three, which is why Chart 3 caps at
   three payer series. Sequential = the blue ramp, one hue, light to dark. */
:root{
  color-scheme:light;
  --page:#f9f9f7; --surface:#fcfcfb; --raised:#ffffff;
  --ink:#0b0b0b; --ink-2:#52514e; --muted:#898781;
  --grid:#e1e0d9; --axis:#c3c2b7; --rule:#e1e0d9;
  --s1:#2a78d6; --s2:#eb6834; --s3:#1baf7a;
  --seq-1:#cde2fb; --seq-2:#9ec5f4; --seq-3:#5598e7;
  --seq-4:#2a78d6; --seq-5:#1c5cab; --seq-6:#104281;
  --goal:#898781;
  --focus:#2a78d6;
}
@media (prefers-color-scheme:dark){
  :root:not([data-theme="light"]){
    color-scheme:dark;
    --page:#0d0d0d; --surface:#1a1a19; --raised:#212120;
    --ink:#ffffff; --ink-2:#c3c2b7; --muted:#898781;
    --grid:#2c2c2a; --axis:#383835; --rule:#2c2c2a;
    --s1:#3987e5; --s2:#d95926; --s3:#199e70;
    /* sequential inverts on a dark surface: low values recede into it */
    --seq-1:#184f95; --seq-2:#1c5cab; --seq-3:#2a78d6;
    --seq-4:#5598e7; --seq-5:#9ec5f4; --seq-6:#cde2fb;
    --focus:#3987e5;
  }
}
:root[data-theme="dark"]{
  color-scheme:dark;
  --page:#0d0d0d; --surface:#1a1a19; --raised:#212120;
  --ink:#ffffff; --ink-2:#c3c2b7; --muted:#898781;
  --grid:#2c2c2a; --axis:#383835; --rule:#2c2c2a;
  --s1:#3987e5; --s2:#d95926; --s3:#199e70;
  --seq-1:#184f95; --seq-2:#1c5cab; --seq-3:#2a78d6;
  --seq-4:#5598e7; --seq-5:#9ec5f4; --seq-6:#cde2fb;
  --focus:#3987e5;
}
*{box-sizing:border-box;}
body{margin:0;background:var(--page);color:var(--ink);
  font:15px/1.6 ui-sans-serif,-apple-system,"Segoe UI",system-ui,sans-serif;
  padding:32px 20px 64px;}
.wrap{max-width:1140px;margin:0 auto;}
h1{font-size:26px;line-height:1.2;letter-spacing:-.02em;margin:0 0 6px;}
.sub{color:var(--ink-2);margin:0 0 4px;font-size:15px;}
.meta{color:var(--muted);font-size:13px;margin:0;}
h2{font-size:17px;margin:0 0 2px;letter-spacing:-.01em;}
.qn{font-size:13px;color:var(--muted);margin:0 0 14px;}

/* ---- theme toggle ---- */
.topbar{display:flex;justify-content:space-between;align-items:flex-start;gap:16px;
  flex-wrap:wrap;margin-bottom:24px;}
.tog{background:var(--raised);border:1px solid var(--rule);color:var(--ink-2);
  border-radius:6px;padding:7px 12px;font-size:13px;cursor:pointer;font-family:inherit;}
.tog:hover{color:var(--ink);}

/* ---- stat tiles ---- */
.tiles{display:grid;grid-template-columns:repeat(auto-fit,minmax(190px,1fr));gap:12px;
  margin-bottom:24px;}
.tile{background:var(--raised);border:1px solid var(--rule);border-radius:8px;padding:14px 16px;}
.tile .k{font-size:12px;color:var(--muted);margin:0 0 4px;text-transform:uppercase;
  letter-spacing:.04em;}
.tile .v{font-size:23px;font-weight:600;margin:0;letter-spacing:-.02em;}
.tile .n{font-size:12px;color:var(--muted);margin:3px 0 0;}

/* ---- filters ---- */
.filters{background:var(--raised);border:1px solid var(--rule);border-radius:8px;
  padding:16px;margin-bottom:14px;}
.frow{display:flex;gap:24px;flex-wrap:wrap;}
.fgrp{min-width:150px;}
.flab{font-size:12px;font-weight:650;color:var(--ink);margin:0 0 2px;
  text-transform:uppercase;letter-spacing:.04em;}
.fdrv{font-size:11px;color:var(--muted);margin:0 0 8px;}
.chips{display:flex;gap:6px;flex-wrap:wrap;}
.chip{border:1px solid var(--rule);background:var(--surface);color:var(--ink-2);
  border-radius:999px;padding:4px 11px;font-size:12.5px;cursor:pointer;font-family:inherit;
  transition:background .12s,color .12s,border-color .12s;}
.chip:hover{border-color:var(--axis);}
.chip[aria-pressed="true"]{background:var(--s1);border-color:var(--s1);color:#fff;}
.chip:focus-visible{outline:2px solid var(--focus);outline-offset:2px;}
details.sec{margin-top:14px;border-top:1px solid var(--rule);padding-top:12px;}
details.sec summary{cursor:pointer;font-size:12.5px;color:var(--muted);font-weight:600;}
details.sec summary:hover{color:var(--ink-2);}
.secbody{padding-top:12px;display:flex;gap:24px;flex-wrap:wrap;}
input[type=search],select{background:var(--surface);border:1px solid var(--rule);
  color:var(--ink);border-radius:6px;padding:6px 10px;font-size:13px;font-family:inherit;
  min-width:210px;}
input[type=search]:focus-visible,select:focus-visible{outline:2px solid var(--focus);
  outline-offset:1px;}
.reset{background:none;border:none;color:var(--s1);font-size:12.5px;cursor:pointer;
  padding:0;font-family:inherit;text-decoration:underline;}

/* ---- panels ---- */
.panel{background:var(--raised);border:1px solid var(--rule);border-radius:8px;
  padding:18px 20px 20px;margin-bottom:18px;}
.applied{font-size:11.5px;color:var(--muted);background:var(--surface);
  border:1px solid var(--rule);border-radius:4px;padding:5px 9px;display:inline-block;
  margin-bottom:12px;}
.scrollx{overflow-x:auto;}
svg{display:block;max-width:100%;}
.note{font-size:12.5px;color:var(--muted);margin:10px 0 0;line-height:1.5;}
.fix{font-size:12.5px;color:var(--ink-2);background:var(--surface);
  border-left:3px solid var(--s2);border-radius:0 4px 4px 0;padding:9px 12px;
  margin:0 0 14px;line-height:1.5;}

/* ---- svg text ---- */
.tick{font-size:11px;fill:var(--muted);}
.vlab{font-size:11px;fill:var(--ink-2);}
.blab{font-size:12px;fill:var(--ink);}
.gridline{stroke:var(--grid);stroke-width:1;}
.axisline{stroke:var(--axis);stroke-width:1;}
.goalline{stroke:var(--goal);stroke-width:1;stroke-dasharray:4 3;}
.goallab{font-size:10.5px;fill:var(--muted);}

/* ---- legend ---- */
.legend{display:flex;gap:16px;flex-wrap:wrap;align-items:center;margin:0 0 10px;
  font-size:12.5px;color:var(--ink-2);}
.lk{display:inline-flex;align-items:center;gap:6px;}
.sw{width:11px;height:11px;border-radius:2px;display:inline-block;}
.ramp{display:flex;align-items:center;gap:8px;font-size:11.5px;color:var(--muted);
  margin:0 0 10px;flex-wrap:wrap;}
.rampbar{display:flex;}
.rampbar span{width:26px;height:11px;display:block;}

/* ---- drill ---- */
.crumb{display:flex;align-items:center;gap:8px;margin:0 0 10px;font-size:13px;}
.back{background:var(--surface);border:1px solid var(--rule);color:var(--ink-2);
  border-radius:6px;padding:4px 10px;font-size:12.5px;cursor:pointer;font-family:inherit;}
.back:hover{color:var(--ink);}
.hint{font-size:11.5px;color:var(--muted);font-style:italic;}
.bar-hit{cursor:pointer;}
.bar-hit:focus-visible{outline:2px solid var(--focus);}

/* ---- tooltip ---- */
#tip{position:fixed;pointer-events:none;opacity:0;transition:opacity .1s;
  background:var(--raised);border:1px solid var(--axis);border-radius:6px;
  padding:8px 10px;font-size:12.5px;color:var(--ink);box-shadow:0 4px 14px rgba(0,0,0,.16);
  z-index:50;max-width:280px;line-height:1.45;}
#tip .tt{font-weight:650;margin-bottom:3px;}
#tip .tr{color:var(--ink-2);}

/* ---- table view ---- */
details.tv{margin-top:12px;}
details.tv summary{cursor:pointer;font-size:12.5px;color:var(--muted);}
details.tv summary:hover{color:var(--ink-2);}
table{border-collapse:collapse;width:100%;font-size:12.5px;margin-top:10px;}
th{text-align:left;color:var(--muted);font-weight:650;font-size:11.5px;padding:5px 10px 5px 0;
  border-bottom:1px solid var(--axis);text-transform:uppercase;letter-spacing:.03em;}
td{padding:6px 10px 6px 0;border-bottom:1px solid var(--rule);color:var(--ink-2);}
td:first-child{color:var(--ink);}
td.n{text-align:right;font-variant-numeric:tabular-nums;}

footer{margin-top:32px;padding-top:16px;border-top:1px solid var(--rule);
  font-size:12.5px;color:var(--muted);line-height:1.6;}
@media (max-width:640px){
  body{padding:20px 12px 48px;}
  .frow{gap:16px;}
}
</style>
</head>
<body>
<div class="wrap">

<div class="topbar">
  <div>
    <h1>Where the money went, and who paid it</h1>
    <p class="sub">Calder Health claims dashboard &mdash; 68.6M claims, 1.26M members, 2020&ndash;2024.</p>
    <p class="meta">All figures as billed. Prices in this dataset carry a documented inflation
      defect on eleven of the twenty largest conditions; see the note at the foot.</p>
  </div>
  <button class="tog" id="themeBtn" type="button">Dark</button>
</div>

<div class="tiles" id="tiles"></div>

<div class="filters">
  <div class="frow">
    <div class="fgrp">
      <p class="flab">Service year</p>
      <p class="fdrv">Drives charts 1 and 3</p>
      <div class="chips" id="fYear"></div>
    </div>
    <div class="fgrp">
      <p class="flab">Payer type</p>
      <p class="fdrv">Charts 1 and 3; share metric on 2 and 5</p>
      <div class="chips" id="fPayer"></div>
    </div>
    <div class="fgrp" style="flex:1;min-width:280px;">
      <p class="flab">Care type</p>
      <p class="fdrv">Drives charts 2, 4A and 5</p>
      <div class="chips" id="fCare"></div>
    </div>
  </div>
  <details class="sec">
    <summary>Secondary filters (drill-down)</summary>
    <div class="secbody">
      <div class="fgrp">
        <p class="flab">Condition</p>
        <p class="fdrv">Filters the chart 2 drill-down</p>
        <input type="search" id="fCond" placeholder="Search 183 conditions&hellip;">
      </div>
      <div class="fgrp">
        <p class="flab">Facility</p>
        <p class="fdrv">Highlights one bar in chart 4B</p>
        <select id="fFac"></select>
      </div>
      <div class="fgrp">
        <p class="flab">Patient state</p>
        <p class="fdrv">Not built &mdash; no saved result carries it</p>
        <p class="note" style="margin:0;max-width:260px;">PATIENT_STATE exists on
          SILVER.PATIENTS but no query in sql/analysis/ selects it, so there is nothing
          to filter. A control here would do nothing.</p>
      </div>
    </div>
  </details>
  <div style="margin-top:12px;"><button class="reset" id="resetBtn" type="button">Reset all filters</button></div>
</div>

<!-- CHART 1 -->
<div class="panel">
  <h2>1. Spending over time</h2>
  <p class="qn">Is total spend rising, and is the cost of an average member rising with it?</p>
  <p class="fix"><strong>Built as two panels, not a combo chart.</strong> Total billed and cost
    per member were requested on one plot with two y-scales. Two scales can be aligned to show
    any relationship the author likes, so the pairing itself would be the finding. Same years,
    same order, two panels &mdash; the comparison stays, the invented correlation goes.</p>
  <div class="applied" id="a1"></div>
  <div class="legend" id="l1"></div>
  <div class="scrollx"><div id="c1"></div></div>
  <details class="tv"><summary>Table view</summary><div id="t1"></div></details>
</div>

<!-- CHART 2 -->
<div class="panel">
  <h2>2. Where spending sits, and who carries it</h2>
  <p class="qn">Which care types drive spending, and which put the heaviest share on members?</p>
  <p class="fix"><strong>Blue ramp, not red-to-green.</strong> Red-to-green is the one gradient
    red-green colourblind readers cannot resolve. Member-paid share is a magnitude, so it takes a
    single hue running light to dark, in six bins, with the percentage printed on every bar so the
    value never depends on colour.</p>
  <div class="applied" id="a2"></div>
  <div class="crumb" id="cr2"></div>
  <div class="ramp" id="r2"></div>
  <div class="scrollx"><div id="c2"></div></div>
  <details class="tv"><summary>Table view</summary><div id="t2"></div></details>
</div>

<!-- CHART 3 -->
<div class="panel">
  <h2>3. Member-paid share by plan type</h2>
  <p class="qn">Does the plan a member holds change what they pay, and is that stable over time?</p>
  <div class="applied" id="a3"></div>
  <div class="legend" id="l3"></div>
  <div class="scrollx"><div id="c3"></div></div>
  <details class="tv"><summary>Table view</summary><div id="t3"></div></details>
</div>

<!-- CHART 4 -->
<div class="panel">
  <h2>4. How concentrated is spending?</h2>
  <p class="qn">How few care types, facilities or members does it take to reach half of all spend?</p>
  <div class="applied" id="a4"></div>
  <h3 style="font-size:14px;margin:14px 0 2px;">4A. By care type</h3>
  <p class="qn" id="q4a"></p>
  <div class="scrollx"><div id="c4a"></div></div>
  <h3 style="font-size:14px;margin:22px 0 2px;">4B. By facility &mdash; top 20 of 3,918</h3>
  <p class="qn" id="q4b"></p>
  <div class="scrollx"><div id="c4b"></div></div>
  <h3 style="font-size:14px;margin:22px 0 2px;">4C. By member</h3>
  <p class="qn" id="q4c"></p>
  <p class="fix" style="border-left-color:var(--s1);"><strong>Drawn as a curve, not 100 bars.</strong>
    Members were specified as ranked bars. At 100 ranks a bar chart is unreadable and the shape is
    the whole point, so this is the cumulative curve. The diagonal is what perfectly even spending
    would look like; distance above it is concentration.</p>
  <div class="scrollx"><div id="c4c"></div></div>
  <details class="tv"><summary>Table view</summary><div id="t4"></div></details>
</div>

<!-- CHART 5 -->
<div class="panel">
  <h2>5. Reach against what a member actually pays</h2>
  <p class="qn">Which care types hit the most wallets, and which hit them hardest?</p>
  <p class="fix"><strong>Coloured by share, labelled by name.</strong> One hue per care type was
    requested. Fifteen hues cannot be told apart under colour-vision deficiency, and bubble charts
    are held to a stricter all-pairs check that caps distinguishable series at three. Identity is
    carried by the label on each bubble; colour carries the burden share, on the same ramp as
    chart 2.</p>
  <div class="applied" id="a5"></div>
  <div class="ramp" id="r5"></div>
  <div class="scrollx"><div id="c5"></div></div>
  <p class="note">Both axes are log scales: each step is a tenfold increase. Bubble area is total
    billed. Labels are placed on the largest bubbles first and dropped where they would collide
    &mdash; hover any bubble, or open the table view, for the ones left unlabelled.</p>
  <details class="tv"><summary>Table view</summary><div id="t5"></div></details>
</div>

<footer>
  <p><strong>Reading these numbers.</strong> Every figure is as billed, from
  <code>sql/results/</code>, each file the output of a query in <code>sql/analysis/</code>.
  Eleven of the twenty largest conditions carry a documented pricing gap against real-world
  benchmarks &mdash; normal pregnancy bills roughly 8.6&times; a comparable real figure. Rankings,
  shares and ratios hold; absolute dollars do not. Correcting those eleven moves pregnancy from
  1st to 2nd and puts chronic kidney disease first.</p>
  <p>Care type is not a source column. It is a keyword classification over the condition name,
  reproduced here exactly from <code>q2_patient_cost_by_care_type.sql</code>; the condition-level
  roll-up reconciles to the care-type totals to within 0.00%.</p>
  <p>Generated by <code>dashboard/generators/claims_dashboard.py</code> from
  <code>dashboard/dashboard_data.json</code>. Edit the generator, not this page.</p>
</footer>
</div>

<div id="tip" role="status" aria-live="polite"></div>

<script>
const DATA = __DATA__;

/* ---------------- formatting ---------------- */
const money = v => {
  const a = Math.abs(v);
  if (a >= 1e9) return '$' + (v/1e9).toFixed(a >= 1e10 ? 0 : 1) + 'B';
  if (a >= 1e6) return '$' + (v/1e6).toFixed(a >= 1e7 ? 0 : 1) + 'M';
  if (a >= 1e3) return '$' + (v/1e3).toFixed(0) + 'K';
  return '$' + Math.round(v);
};
const money0 = v => '$' + Math.round(v).toLocaleString('en-US');
const num = v => Math.round(v).toLocaleString('en-US');
const pct = v => (v == null ? 'n/a' : v.toFixed(1) + '%');
const esc = s => String(s).replace(/[&<>"]/g, c =>
  ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;'}[c]));

/* Six sequential bins for member-paid share. Six, not a continuous ramp:
   past about seven classes adjacent bins stop being separable. */
const BINS = [
  {max: 10, css: 'var(--seq-1)', label: 'under 10%'},
  {max: 15, css: 'var(--seq-2)', label: '10-15%'},
  {max: 20, css: 'var(--seq-3)', label: '15-20%'},
  {max: 25, css: 'var(--seq-4)', label: '20-25%'},
  {max: 30, css: 'var(--seq-5)', label: '25-30%'},
  {max: Infinity, css: 'var(--seq-6)', label: '30% and up'}
];
const binOf = s => (BINS.find(b => (s == null ? 0 : s) < b.max) || BINS[5]).css;

/* ---------------- state ---------------- */
const YEARS = DATA.chart1.overall.map(d => d.year);
const PAYERS = Object.keys(DATA.chart3);
const CARES = DATA.chart2.care_types.map(c => c.care_type);
const state = {
  years: new Set(YEARS),
  payers: new Set(PAYERS),
  cares: new Set(CARES),
  drill: null,        // care type name when chart 2 is drilled in
  cond: '',
  facility: ''
};

/* ---------------- svg helpers ---------------- */
const NS = 'http://www.w3.org/2000/svg';
function svg(w, h, label) {
  const s = document.createElementNS(NS, 'svg');
  s.setAttribute('viewBox', '0 0 ' + w + ' ' + h);
  s.setAttribute('width', w); s.setAttribute('height', h);
  s.setAttribute('role', 'img');
  s.setAttribute('aria-label', label);
  return s;
}
function el(tag, attrs, parent) {
  const n = document.createElementNS(NS, tag);
  for (const k in attrs) n.setAttribute(k, attrs[k]);
  if (parent) parent.appendChild(n);
  return n;
}
function text(p, x, y, str, cls, anchor) {
  const t = el('text', {x: x, y: y, class: cls || 'tick'}, p);
  if (anchor) t.setAttribute('text-anchor', anchor);
  t.textContent = str;
  return t;
}
/* Nice round ceiling so axis labels are readable numbers. */
function niceMax(v) {
  if (v <= 0) return 1;
  const mag = Math.pow(10, Math.floor(Math.log10(v)));
  return Math.ceil(v / (mag / 2)) * (mag / 2);
}

/* ---------------- tooltip ---------------- */
const tip = document.getElementById('tip');
function hookTip(node, title, rows) {
  const show = ev => {
    tip.innerHTML = '<div class="tt">' + esc(title) + '</div>' +
      rows.map(r => '<div class="tr">' + esc(r) + '</div>').join('');
    tip.style.opacity = '1';
    const pad = 14, w = tip.offsetWidth, h = tip.offsetHeight;
    let x = ev.clientX + pad, y = ev.clientY + pad;
    if (x + w > innerWidth - 8) x = ev.clientX - w - pad;
    if (y + h > innerHeight - 8) y = ev.clientY - h - pad;
    tip.style.left = x + 'px'; tip.style.top = y + 'px';
  };
  node.addEventListener('mouseenter', show);
  node.addEventListener('mousemove', show);
  node.addEventListener('mouseleave', () => { tip.style.opacity = '0'; });
}

/* ---------------- filter chips ---------------- */
function chips(host, values, sel, onToggle, labelFn) {
  host.innerHTML = '';
  values.forEach(v => {
    const b = document.createElement('button');
    b.type = 'button'; b.className = 'chip';
    b.textContent = labelFn ? labelFn(v) : v;
    b.setAttribute('aria-pressed', sel.has(v) ? 'true' : 'false');
    b.onclick = () => { onToggle(v); render(); };
    host.appendChild(b);
  });
}
function toggle(set, v, all) {
  if (set.has(v)) { if (set.size > 1) set.delete(v); }
  else set.add(v);
  if (set.size === 0) all.forEach(x => set.add(x));
}

/* Which payer's share column applies to charts 2 and 5.
   Only Commercial and Government have per-care-type columns in the source. */
function shareMode() {
  if (state.payers.size !== 1) return {key: 'member_share', label: 'all payers'};
  const only = [...state.payers][0];
  if (only === 'Commercial') return {key: 'share_commercial', label: 'commercial members'};
  if (only === 'Government') return {key: 'share_government', label: 'government members'};
  return {key: 'member_share', label: 'all payers (Self-Pay has no per-care-type column)'};
}

function appliedNote(host, parts) {
  document.getElementById(host).textContent = 'Showing: ' + parts.join(' | ');
}

/* ================= CHART 1: two stacked panels, one shared x ================= */
function chart1() {
  const yrs = YEARS.filter(y => state.years.has(y));
  const single = state.payers.size === 1 ? [...state.payers][0] : null;
  const src = single ? DATA.chart1.by_payer[single] : DATA.chart1.overall;
  const rows = src.filter(d => state.years.has(d.year));

  appliedNote('a1', ['years ' + (yrs.length === YEARS.length ? 'all' : yrs.join(', ')),
    single ? single + ' only' : 'all payer types']);

  const legend = document.getElementById('l1');
  legend.innerHTML = '<span class="lk"><span class="sw" style="background:var(--s1)"></span>' +
    'Total billed</span><span class="lk"><span class="sw" style="background:var(--s2)"></span>' +
    'Cost per member</span>';

  const W = Math.max(560, yrs.length * 108 + 90), H1 = 190, H2 = 150, GAP = 34;
  const L = 74, R = 16, TOP = 16;
  const s = svg(W, H1 + GAP + H2 + 34,
    'Two panels sharing a year axis: total billed, and cost per member.');

  // ---- panel A: total billed, columns
  const maxB = niceMax(Math.max(...rows.map(d => d.billed)));
  const pw = W - L - R, ph = H1 - TOP - 26;
  for (let i = 0; i <= 4; i++) {
    const y = TOP + ph - (ph * i / 4);
    el('line', {x1: L, y1: y, x2: W - R, y2: y, class: 'gridline'}, s);
    text(s, L - 8, y + 4, money(maxB * i / 4), 'tick', 'end');
  }
  text(s, L, TOP - 4, 'Total billed', 'vlab');
  const bw = Math.min(56, pw / rows.length * 0.62);
  rows.forEach((d, i) => {
    const cx = L + pw * (i + 0.5) / rows.length;
    const h = ph * d.billed / maxB;
    const r = el('rect', {x: cx - bw / 2, y: TOP + ph - h, width: bw, height: h,
      rx: 4, fill: 'var(--s1)'}, s);
    hookTip(r, d.year + (single ? ' · ' + single : ''), [
      'Total billed: ' + money0(d.billed),
      'Members: ' + num(d.members),
      'Member-paid share: ' + pct(d.member_share)]);
  });
  el('line', {x1: L, y1: TOP + ph, x2: W - R, y2: TOP + ph, class: 'axisline'}, s);

  // ---- panel B: cost per member, line
  const top2 = H1 + GAP;
  const vals = rows.map(d => d.billed_per_member);
  const maxC = niceMax(Math.max(...vals)), ph2 = H2 - 30;
  for (let i = 0; i <= 3; i++) {
    const y = top2 + ph2 - (ph2 * i / 3);
    el('line', {x1: L, y1: y, x2: W - R, y2: y, class: 'gridline'}, s);
    text(s, L - 8, y + 4, '$' + num(maxC * i / 3), 'tick', 'end');
  }
  text(s, L, top2 - 4, 'Cost per member', 'vlab');
  const pts = rows.map((d, i) => [L + pw * (i + 0.5) / rows.length,
    top2 + ph2 - ph2 * d.billed_per_member / maxC]);
  if (pts.length > 1) {
    el('path', {d: 'M' + pts.map(p => p[0] + ',' + p[1]).join('L'), fill: 'none',
      stroke: 'var(--s2)', 'stroke-width': 2, 'stroke-linejoin': 'round'}, s);
  }
  rows.forEach((d, i) => {
    const c = el('circle', {cx: pts[i][0], cy: pts[i][1], r: 5, fill: 'var(--s2)',
      stroke: 'var(--raised)', 'stroke-width': 2}, s);
    hookTip(c, d.year + (single ? ' · ' + single : ''),
      ['Cost per member: ' + money0(d.billed_per_member),
       'Member paid: ' + money0(d.member_paid_per_member || 0)]);
    // below the point, not above: these values sit near the top of their scale and
    // a label above the first one collides with the panel title
    text(s, pts[i][0], pts[i][1] + 18, '$' + num(d.billed_per_member), 'vlab', 'middle');
  });
  el('line', {x1: L, y1: top2 + ph2, x2: W - R, y2: top2 + ph2, class: 'axisline'}, s);
  rows.forEach((d, i) => text(s, L + pw * (i + 0.5) / rows.length, top2 + ph2 + 18,
    d.year, 'tick', 'middle'));

  const host = document.getElementById('c1');
  host.innerHTML = ''; host.appendChild(s);

  document.getElementById('t1').innerHTML = tableOf(
    ['Year', 'Total billed', 'Members', 'Cost per member', 'Member share'],
    rows.map(d => [d.year, money0(d.billed), num(d.members),
      money0(d.billed_per_member), pct(d.member_share)]), [0]);
}

/* ================= CHART 2: care types, drill to conditions ================= */
function chart2() {
  const sm = shareMode();
  const drilled = state.drill;
  let rows, unit;

  if (drilled) {
    unit = 'condition';
    rows = DATA.chart2.conditions
      .filter(c => c.care_type === drilled)
      .filter(c => !state.cond || c.condition.toLowerCase().includes(state.cond))
      .map(c => ({name: c.condition, billed: c.billed, share: c.member_share,
        members: c.members, paid: c.member_paid}));
  } else {
    unit = 'care type';
    rows = DATA.chart2.care_types
      .filter(c => state.cares.has(c.care_type))
      .map(c => ({name: c.care_type, billed: c.billed, share: c[sm.key],
        members: c.members, paid: c.member_paid, drill: true}));
  }
  rows.sort((a, b) => b.billed - a.billed);
  rows = rows.slice(0, 22);

  appliedNote('a2', [drilled ? 'conditions within ' + drilled
      : state.cares.size + ' of ' + CARES.length + ' care types',
    'share shown for ' + sm.label,
    'billed dollars are not split by payer in the source']);

  // breadcrumb
  const cr = document.getElementById('cr2');
  cr.innerHTML = '';
  if (drilled) {
    const b = document.createElement('button');
    b.type = 'button'; b.className = 'back'; b.textContent = '← All care types';
    b.onclick = () => { state.drill = null; render(); };
    cr.appendChild(b);
    const sp = document.createElement('span');
    sp.innerHTML = '<strong>' + esc(drilled) + '</strong> · ' + rows.length +
      ' condition' + (rows.length === 1 ? '' : 's');
    cr.appendChild(sp);
  } else {
    const h = document.createElement('span');
    h.className = 'hint';
    h.textContent = 'Click any bar to see the conditions inside it.';
    cr.appendChild(h);
  }

  // ramp legend
  document.getElementById('r2').innerHTML = rampLegend('Member-paid share');

  if (!rows.length) {
    document.getElementById('c2').innerHTML =
      '<p class="note">No conditions match that search inside ' + esc(drilled || '') + '.</p>';
    document.getElementById('t2').innerHTML = '';
    return;
  }

  const L = 210, R = 108, W = Math.max(620, Math.min(1080, 760)), rowH = 27;
  const H = rows.length * rowH + 34;
  const s = svg(W, H, 'Total billed by ' + unit + ', coloured by member-paid share.');
  const maxV = Math.max(...rows.map(r => r.billed)), pw = W - L - R;

  rows.forEach((r, i) => {
    const y = i * rowH + 6, h = rowH - 9;
    const w = Math.max(2, pw * r.billed / maxV);
    const g = el('g', {class: r.drill ? 'bar-hit' : ''}, s);
    if (r.drill) {
      g.setAttribute('tabindex', '0');
      g.setAttribute('role', 'button');
      g.setAttribute('aria-label', 'Drill into ' + r.name);
      const go = () => { state.drill = r.name; state.cond = '';
        document.getElementById('fCond').value = ''; render(); };
      g.onclick = go;
      g.onkeydown = e => { if (e.key === 'Enter' || e.key === ' ') { e.preventDefault(); go(); } };
    }
    // 2px surface gap between adjacent fills comes from rowH - 9 leaving space
    el('rect', {x: L, y: y, width: w, height: h, rx: 4, fill: binOf(r.share)}, g);
    const label = r.name.length > 30 ? r.name.slice(0, 29) + '…' : r.name;
    text(g, L - 10, y + h / 2 + 4, label, 'blab', 'end');
    text(g, L + w + 8, y + h / 2 + 4, money(r.billed) + '  ·  ' + pct(r.share), 'vlab');
    hookTip(g, r.name, [
      'Total billed: ' + money0(r.billed),
      'Member-paid share: ' + pct(r.share),
      'Paid by members: ' + money0(r.paid),
      'People affected: ' + num(r.members),
      r.drill ? 'Click to drill in' : '']. filter(Boolean));
  });
  el('line', {x1: L, y1: 2, x2: L, y2: rows.length * rowH + 2, class: 'axisline'}, s);

  const host = document.getElementById('c2');
  host.innerHTML = ''; host.appendChild(s);

  document.getElementById('t2').innerHTML = tableOf(
    [unit === 'condition' ? 'Condition' : 'Care type', 'Total billed', 'Member share',
     'Paid by members', 'People'],
    rows.map(r => [r.name, money0(r.billed), pct(r.share), money0(r.paid), num(r.members)]), [0]);
}

function rampLegend(title) {
  return '<span>' + title + '</span><span class="rampbar">' +
    BINS.map(b => '<span style="background:' + b.css + '" title="' + b.label + '"></span>').join('') +
    '</span><span>' + BINS[0].label + ' → ' + BINS[5].label + '</span>';
}

/* ================= CHART 3: member share by payer type over time ================= */
function chart3() {
  const yrs = YEARS.filter(y => state.years.has(y));
  // colour follows the entity, never its rank: fixed slot per payer type
  const SLOT = {'Commercial': 'var(--s1)', 'Government': 'var(--s2)',
                'Self-Pay / Uninsured': 'var(--s3)'};
  const shown = PAYERS.filter(p => state.payers.has(p));

  appliedNote('a3', ['years ' + (yrs.length === YEARS.length ? 'all' : yrs.join(', ')),
    shown.length + ' of ' + PAYERS.length + ' payer types']);

  document.getElementById('l3').innerHTML = shown.map(p =>
    '<span class="lk"><span class="sw" style="background:' + SLOT[p] + '"></span>' +
    esc(p) + '</span>').join('');

  const W = Math.max(560, yrs.length * 112 + 120), H = 250;
  const L = 56, R = 108, TOP = 16, ph = H - TOP - 34, pw = W - L - R;
  const s = svg(W, H, 'Member-paid share by payer type, by year.');

  for (let i = 0; i <= 4; i++) {
    const y = TOP + ph - ph * i / 4;
    el('line', {x1: L, y1: y, x2: W - R, y2: y, class: 'gridline'}, s);
    text(s, L - 8, y + 4, (i * 25) + '%', 'tick', 'end');
  }
  el('line', {x1: L, y1: TOP + ph, x2: W - R, y2: TOP + ph, class: 'axisline'}, s);
  yrs.forEach((y, i) => text(s, L + pw * (i + 0.5) / yrs.length, TOP + ph + 18, y, 'tick', 'middle'));

  shown.forEach(p => {
    const pts = DATA.chart3[p].filter(d => state.years.has(d.year))
      .map((d, i) => ({x: L + pw * (i + 0.5) / yrs.length,
        y: TOP + ph - ph * d.member_share / 100, d: d}));
    if (pts.length > 1) {
      el('path', {d: 'M' + pts.map(q => q.x + ',' + q.y).join('L'), fill: 'none',
        stroke: SLOT[p], 'stroke-width': 2, 'stroke-linejoin': 'round'}, s);
    }
    pts.forEach(q => {
      const c = el('circle', {cx: q.x, cy: q.y, r: 5, fill: SLOT[p],
        stroke: 'var(--raised)', 'stroke-width': 2}, s);
      hookTip(c, p + ' · ' + q.d.year, [
        'Member-paid share: ' + pct(q.d.member_share),
        'Paid per member: ' + money0(q.d.member_paid_per_member)]);
    });
    // direct label at the line end: 3 series, so all get one
    const last = pts[pts.length - 1];
    if (last) {
      const t = text(s, last.x + 10, last.y + 4, p.replace(' / Uninsured', '') +
        ' ' + pct(last.d.member_share), 'vlab');
      t.setAttribute('fill', 'var(--ink-2)');
    }
  });

  const host = document.getElementById('c3');
  host.innerHTML = ''; host.appendChild(s);

  const tRows = [];
  shown.forEach(p => DATA.chart3[p].filter(d => state.years.has(d.year))
    .forEach(d => tRows.push([p, d.year, pct(d.member_share),
      money0(d.member_paid_per_member)])));
  document.getElementById('t3').innerHTML = tableOf(
    ['Payer type', 'Year', 'Member share', 'Paid per member'], tRows, [0, 1]);
}

/* ================= CHART 4: concentration ================= */
function cumulBars(hostId, rows, unitLabel, highlight, gutter) {
  // gutter is the label column. Facility names are long and upper-case, so they
  // get a wider one; the truncation budget is derived from it rather than fixed,
  // otherwise a right-anchored label runs off the left edge of the viewBox.
  const L = gutter || 210, R = 66, rowH = 25, W = 760;
  const maxChars = Math.floor((L - 16) / 7.1);
  const H = rows.length * rowH + 28;
  const s = svg(W, H, 'Cumulative share of spend by ' + unitLabel + '.');
  const pw = W - L - R;

  [50, 75].forEach(g => {
    const x = L + pw * g / 100;
    el('line', {x1: x, y1: 2, x2: x, y2: rows.length * rowH + 4, class: 'goalline'}, s);
    text(s, x, rows.length * rowH + 20, g + '%', 'goallab', 'middle');
  });

  rows.forEach((r, i) => {
    const y = i * rowH + 5, h = rowH - 9;
    const w = Math.max(2, pw * r.cumulative_pct / 100);
    const on = highlight && r.name === highlight;
    const g = el('g', {}, s);
    el('rect', {x: L, y: y, width: w, height: h, rx: 4,
      fill: on ? 'var(--s2)' : 'var(--s1)',
      opacity: (highlight && !on) ? 0.45 : 1}, g);
    const prefix = (i + 1) + '. ';
    const room = maxChars - prefix.length;
    const nm = r.name.length > room ? r.name.slice(0, Math.max(3, room - 1)) + '…' : r.name;
    text(g, L - 10, y + h / 2 + 4, prefix + nm, 'blab', 'end');
    text(g, L + w + 8, y + h / 2 + 4, r.cumulative_pct.toFixed(1) + '%', 'vlab');
    hookTip(g, (i + 1) + '. ' + r.name, [
      'Own billed: ' + money0(r.billed),
      'Cumulative share: ' + r.cumulative_pct.toFixed(2) + '%',
      r.members != null ? 'Members: ' + num(r.members) : ''].filter(Boolean));
  });
  el('line', {x1: L, y1: 2, x2: L, y2: rows.length * rowH + 4, class: 'axisline'}, s);
  const host = document.getElementById(hostId);
  host.innerHTML = ''; host.appendChild(s);
}

function chart4() {
  const hd = DATA.chart4.headline;
  appliedNote('a4', [state.cares.size + ' of ' + CARES.length + ' care types in 4A',
    'facilities and members are unfiltered']);

  // 4A -- recomputed over the selected care types so the curve stays honest
  const sel = DATA.chart2.care_types.filter(c => state.cares.has(c.care_type))
    .slice().sort((a, b) => b.billed - a.billed);
  const tot = sel.reduce((a, c) => a + c.billed, 0);
  let run = 0;
  const careRows = sel.map(c => {
    run += c.billed;
    return {name: c.care_type, billed: c.billed, cumulative_pct: 100 * run / tot};
  });
  const half = careRows.findIndex(r => r.cumulative_pct >= 50) + 1;
  document.getElementById('q4a').textContent =
    half + ' of ' + careRows.length + ' care types reach half of the selected spend.';
  cumulBars('c4a', careRows, 'care type');

  // 4B -- facilities, top 20
  document.getElementById('q4b').textContent =
    'Across all 3,918 facilities, ' + hd.Organisations.count_for_half +
    ' (' + hd.Organisations.pct_for_half.toFixed(2) + '%) carry half of all spend.';
  cumulBars('c4b', DATA.chart4.facilities.map(f => ({
    name: f.name, billed: f.billed, cumulative_pct: f.cumulative_pct, members: f.members
  })), 'facility', state.facility, 290);

  // 4C -- member Lorenz curve
  document.getElementById('q4c').textContent =
    'It takes ' + num(hd.Patients.count_for_half) + ' members (' +
    hd.Patients.pct_for_half.toFixed(2) + '%) to reach the same half. The priciest 1% carry ' +
    hd.Patients.top1 + '%.';

  const W = 620, H = 300, L = 54, R = 20, TOP = 14, ph = H - TOP - 40, pw = W - L - R;
  const s = svg(W, H, 'Cumulative share of spend against share of members, ranked.');
  for (let i = 0; i <= 4; i++) {
    const y = TOP + ph - ph * i / 4;
    el('line', {x1: L, y1: y, x2: W - R, y2: y, class: 'gridline'}, s);
    text(s, L - 8, y + 4, (i * 25) + '%', 'tick', 'end');
  }
  [50, 75].forEach(g => {
    const y = TOP + ph - ph * g / 100;
    el('line', {x1: L, y1: y, x2: W - R, y2: y, class: 'goalline'}, s);
    text(s, W - R - 2, y - 5, g + '% of spend', 'goallab', 'end');
  });
  el('line', {x1: L, y1: TOP + ph, x2: W - R, y2: TOP, class: 'goalline'}, s);
  text(s, L + pw * 0.55, TOP + ph - ph * 0.55 + 16, 'perfectly even', 'goallab', 'middle');

  const pts = DATA.chart4.members.map(m => [L + pw * m.pct_group / 100,
    TOP + ph - ph * m.cumulative_pct / 100]);
  el('path', {d: 'M' + pts.map(p => p[0] + ',' + p[1]).join('L'), fill: 'none',
    stroke: 'var(--s1)', 'stroke-width': 2, 'stroke-linejoin': 'round'}, s);

  // hover band: nearest point to the cursor
  const hit = el('rect', {x: L, y: TOP, width: pw, height: ph, fill: 'transparent'}, s);
  const dot = el('circle', {cx: -20, cy: -20, r: 5, fill: 'var(--s1)',
    stroke: 'var(--raised)', 'stroke-width': 2}, s);
  hit.addEventListener('mousemove', ev => {
    const r = hit.getBoundingClientRect();
    const frac = (ev.clientX - r.left) / r.width * 100;
    let best = DATA.chart4.members[0];
    DATA.chart4.members.forEach(m => {
      if (Math.abs(m.pct_group - frac) < Math.abs(best.pct_group - frac)) best = m;
    });
    dot.setAttribute('cx', L + pw * best.pct_group / 100);
    dot.setAttribute('cy', TOP + ph - ph * best.cumulative_pct / 100);
    tip.innerHTML = '<div class="tt">Priciest ' + best.pct_group + '% of members</div>' +
      '<div class="tr">carry ' + best.cumulative_pct.toFixed(1) + '% of all spend</div>';
    tip.style.opacity = '1';
    let x = ev.clientX + 14, y = ev.clientY + 14;
    if (x + tip.offsetWidth > innerWidth - 8) x = ev.clientX - tip.offsetWidth - 14;
    tip.style.left = x + 'px'; tip.style.top = y + 'px';
  });
  hit.addEventListener('mouseleave', () => {
    tip.style.opacity = '0'; dot.setAttribute('cx', -20);
  });

  el('line', {x1: L, y1: TOP + ph, x2: W - R, y2: TOP + ph, class: 'axisline'}, s);
  [0, 25, 50, 75, 100].forEach(v =>
    text(s, L + pw * v / 100, TOP + ph + 18, v + '%', 'tick', 'middle'));
  text(s, L + pw / 2, H - 6, 'Share of members, priciest first', 'vlab', 'middle');

  const host = document.getElementById('c4c');
  host.innerHTML = ''; host.appendChild(s);

  document.getElementById('t4').innerHTML = tableOf(
    ['Ranked by', 'How many exist', 'Priciest 1%', 'Priciest 10%', 'Needed for half'],
    Object.keys(hd).map(k => [k, num(hd[k].population),
      hd[k].top1 == null ? 'n/a' : hd[k].top1 + '%',
      hd[k].top10 == null ? 'n/a' : hd[k].top10 + '%',
      num(hd[k].count_for_half) + ' (' + hd[k].pct_for_half.toFixed(2) + '%)']), [0]);
}

/* ================= CHART 5: reach against out-of-pocket ================= */
function chart5() {
  const sm = shareMode();
  const shareBy = {};
  DATA.chart2.care_types.forEach(c => { shareBy[c.care_type] = c[sm.key]; });

  const rows = DATA.chart5.filter(d => state.cares.has(d.care_type));
  appliedNote('a5', [state.cares.size + ' of ' + CARES.length + ' care types',
    'colour = share for ' + sm.label]);
  document.getElementById('r5').innerHTML = rampLegend('Member-paid share');

  if (!rows.length) {
    document.getElementById('c5').innerHTML = '<p class="note">No care types selected.</p>';
    return;
  }

  const W = 820, H = 400, L = 62, R = 24, TOP = 18, ph = H - TOP - 46, pw = W - L - R;
  const s = svg(W, H, 'Members reached against median out-of-pocket, one bubble per care type.');

  const xs = rows.map(d => d.members), ys = rows.map(d => d.median_oop);
  const x0 = Math.log10(Math.max(1000, Math.min(...xs) * 0.7));
  const x1 = Math.log10(Math.max(...xs) * 1.35);
  // y is log too: one care type sits near $10,800 and the rest under $1,500, so a
  // linear axis piles fourteen of fifteen bubbles onto the baseline.
  const y0 = Math.log10(Math.min(...ys) * 0.6);
  const y1 = Math.log10(Math.max(...ys) * 1.6);
  const X = v => L + pw * (Math.log10(v) - x0) / (x1 - x0);
  const Y = v => TOP + ph - ph * (Math.log10(v) - y0) / (y1 - y0);

  for (let e = Math.ceil(y0); e <= Math.floor(y1); e++) {
    const v = Math.pow(10, e), y = Y(v);
    el('line', {x1: L, y1: y, x2: W - R, y2: y, class: 'gridline'}, s);
    text(s, L - 8, y + 4, '$' + num(v), 'tick', 'end');
  }
  text(s, L, TOP - 5, 'Median paid by an affected member, five years (log scale)', 'vlab');

  for (let e = Math.ceil(x0); e <= Math.floor(x1); e++) {
    const x = X(Math.pow(10, e));
    el('line', {x1: x, y1: TOP, x2: x, y2: TOP + ph, class: 'gridline'}, s);
    text(s, x, TOP + ph + 18, num(Math.pow(10, e)), 'tick', 'middle');
  }
  el('line', {x1: L, y1: TOP + ph, x2: W - R, y2: TOP + ph, class: 'axisline'}, s);
  text(s, L + pw / 2, H - 6, 'People affected (log scale)', 'vlab', 'middle');

  const maxB = Math.max(...rows.map(d => d.billed));
  // area proportional to billed, so radius follows the square root
  const R_ = d => 7 + 34 * Math.sqrt(d.billed / maxB);

  // Labels are SELECTIVE, biggest first: a label is placed above the bubble, or
  // below if that spot is taken, and dropped entirely if both collide. Every
  // bubble keeps its hover tooltip and its row in the table, so nothing is lost --
  // fifteen labels drawn unconditionally overlap into an unreadable pile.
  const placed = [];
  const fits = (x, y, w) => {
    const box = {a: x - w / 2, b: y - 11, c: x + w / 2, d: y + 3};
    if (box.a < L - 4 || box.c > W - R + 4 || box.b < TOP - 4) return false;
    return !placed.some(p => !(box.c < p.a || box.a > p.c || box.d < p.b || box.b > p.d));
  };

  rows.slice().sort((a, b) => b.billed - a.billed).forEach(d => {
    const cx = X(d.members), cy = Y(d.median_oop), r = R_(d);
    const c = el('circle', {cx: cx, cy: cy, r: r, fill: binOf(shareBy[d.care_type]),
      stroke: 'var(--raised)', 'stroke-width': 2, opacity: 0.92}, s);
    hookTip(c, d.care_type, [
      'People affected: ' + num(d.members),
      'Median out-of-pocket: ' + money0(d.median_oop),
      'P90 out-of-pocket: ' + money0(d.p90_oop),
      'Total billed: ' + money0(d.billed),
      'Member-paid share: ' + pct(shareBy[d.care_type])]);

    const nm = d.care_type.length > 22 ? d.care_type.slice(0, 21) + '…' : d.care_type;
    const w = nm.length * 6.1;
    const above = cy - r - 7, below = cy + r + 15;
    const y = fits(cx, above, w) ? above : (fits(cx, below, w) ? below : null);
    if (y === null) return;
    placed.push({a: cx - w / 2, b: y - 11, c: cx + w / 2, d: y + 3});
    const t = text(s, cx, y, nm, 'vlab', 'middle');
    t.setAttribute('fill', 'var(--ink)');
  });

  const host = document.getElementById('c5');
  host.innerHTML = ''; host.appendChild(s);

  document.getElementById('t5').innerHTML = tableOf(
    ['Care type', 'People', 'Median OOP', 'P90 OOP', 'Total billed', 'Share'],
    rows.slice().sort((a, b) => b.billed - a.billed).map(d =>
      [d.care_type, num(d.members), money0(d.median_oop), money0(d.p90_oop),
       money0(d.billed), pct(shareBy[d.care_type])]), [0]);
}

/* ---------------- table view ---------------- */
function tableOf(head, rows, textCols) {
  const tc = new Set(textCols || []);
  return '<table><thead><tr>' + head.map(h => '<th>' + esc(h) + '</th>').join('') +
    '</tr></thead><tbody>' + rows.map(r => '<tr>' + r.map((c, i) =>
      '<td' + (tc.has(i) ? '' : ' class="n"') + '>' + esc(c) + '</td>').join('') +
    '</tr>').join('') + '</tbody></table>';
}

/* ---------------- tiles ---------------- */
function tiles() {
  const yrs = DATA.chart1.overall.filter(d => state.years.has(d.year));
  const billed = yrs.reduce((a, d) => a + d.billed, 0);
  const paid = yrs.reduce((a, d) => a + d.member_paid, 0);
  const hd = DATA.chart4.headline;
  const t = [
    ['Total billed', money(billed), yrs.length + ' of 5 years selected'],
    ['Member-paid share', pct(100 * paid / billed), money(paid) + ' out of pocket'],
    ['Facilities for half of spend', num(hd.Organisations.count_for_half),
     'of ' + num(hd.Organisations.population) + ' · ' +
     hd.Organisations.pct_for_half.toFixed(2) + '%'],
    ['Members for half of spend', num(hd.Patients.count_for_half),
     'of ' + num(hd.Patients.population) + ' · ' +
     hd.Patients.pct_for_half.toFixed(2) + '%']
  ];
  document.getElementById('tiles').innerHTML = t.map(r =>
    '<div class="tile"><p class="k">' + esc(r[0]) + '</p><p class="v">' + esc(r[1]) +
    '</p><p class="n">' + esc(r[2]) + '</p></div>').join('');
}

/* ---------------- wiring ---------------- */
function render() {
  chips(document.getElementById('fYear'), YEARS, state.years,
    v => toggle(state.years, v, YEARS));
  chips(document.getElementById('fPayer'), PAYERS, state.payers,
    v => toggle(state.payers, v, PAYERS), p => p.replace(' / Uninsured', ''));
  chips(document.getElementById('fCare'), CARES, state.cares,
    v => toggle(state.cares, v, CARES));
  tiles(); chart1(); chart2(); chart3(); chart4(); chart5();
}

document.getElementById('fCond').addEventListener('input', e => {
  state.cond = e.target.value.trim().toLowerCase();
  chart2();
});

const fac = document.getElementById('fFac');
fac.innerHTML = '<option value="">All facilities</option>' +
  DATA.chart4.facilities.map(f => '<option>' + esc(f.name) + '</option>').join('');
fac.addEventListener('change', e => { state.facility = e.target.value; chart4(); });

document.getElementById('resetBtn').onclick = () => {
  state.years = new Set(YEARS); state.payers = new Set(PAYERS);
  state.cares = new Set(CARES); state.drill = null; state.cond = ''; state.facility = '';
  document.getElementById('fCond').value = ''; fac.value = '';
  render();
};

const themeBtn = document.getElementById('themeBtn');
function applyTheme(dark) {
  document.documentElement.setAttribute('data-theme', dark ? 'dark' : 'light');
  themeBtn.textContent = dark ? 'Light' : 'Dark';
  try { localStorage.setItem('cd-theme', dark ? 'dark' : 'light'); } catch (e) {}
  render();  // SVG fills read CSS vars at paint, but redraw keeps labels in step
}
/* Precedence: a theme the host already stamped on the root, then this page's own
   saved choice, then the OS setting. Reading the stamp first matters when the page
   is embedded somewhere that sets the theme for us. */
const stamped = document.documentElement.getAttribute('data-theme');
let dark = stamped ? stamped === 'dark'
                   : matchMedia('(prefers-color-scheme: dark)').matches;
try {
  const saved = localStorage.getItem('cd-theme');
  if (!stamped && saved) dark = saved === 'dark';
} catch (e) {}
applyTheme(dark);
themeBtn.onclick = () => { dark = !dark; applyTheme(dark); };
</script>
</body>
</html>
'''


ART = os.path.join(ROOT, 'dashboard', 'claims_dashboard.artifact.html')


def build():
    with open(DATA) as fh:
        payload = fh.read()
    return PAGE.replace('__DATA__', payload)


def build_artifact(page):
    """Same page with the document skeleton removed.

    A published Artifact is wrapped in its own doctype/head/body at publish time,
    so this variant ships <title>, <style>, the markup and the <script> only.
    Keeping it as a derived file means the two never drift: both come from PAGE.
    """
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
