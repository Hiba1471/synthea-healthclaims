#!/usr/bin/env python3
"""Generate dashboard/where_the_money_goes.html -- the three-panel Q1 chart.

    python3 dashboard/generators/where_the_money_goes.py

Written 2026-08-29 to replace a generator lost with a session scratch directory.
This is the only chart in the project holding three figures in one page, so it
reads three result files:

  1. bars    -- top 20 conditions by total billed   q1_spend_decomposition
  2. dots    -- patients against cost per patient   q1_spend_decomposition
  3. spread  -- cost per claim across hospitals     q1_hospital_variability

THE SUBTITLE NAMES BOTH DENOMINATORS AND MUST KEEP DOING SO. Panel 1 says the
top 20 cover "90.8% of condition-attributable spend and 66.6% of all spend",
giving the reader both figures rather than letting one stand for the other. This
chart is the reason that convention exists in the project; concentration.html
broke it and had to be corrected. Do not shorten it to "of all spending".

PANEL 3 NEEDED A NEW COLUMN. The box is drawn between P25 and P75, and those
quartiles are NOT symmetric about the median -- for Normal pregnancy they sit at
$4,745 and $15,768 against a median of $11,499. Reconstructing the box as
median +/- half the IQR, which the old columns would have allowed, is visibly
wrong. q1_hospital_variability.sql had computed both quartiles all along and
discarded them, so it now emits them and this reads them directly. Without that
change the panel could not be regenerated at all.

Nine of 1,153 numbers differ from the chart this replaces, all by 0.1px, all in
panel 3. The chart was built from a marginally different median -- 516.3px
implies about $11,504 where the current CSV gives $11,498.66. A sixth of a pixel
of difference, invisible, and the current CSV is the source of truth.

Display names are shortened for the axis and differ per panel -- the same
condition is "Non-small cell lung carcinoma" in panel 1 and "Non-small cell lung
cancer" in panel 2. The three maps below preserve that; they were lifted from
the chart this replaces rather than invented.
"""
import csv, math, os

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
SPEND = os.path.join(ROOT, 'sql/results/q1_spend_decomposition_2020_2024.csv')
VAR   = os.path.join(ROOT, 'sql/results/q1_hospital_variability_2020_2024.csv')
OUT   = os.path.join(ROOT, 'dashboard/where_the_money_goes.html')

TOP_N, SPREAD_N = 20, 10

# --- panel 1: horizontal bars -------------------------------------------
B_X, B_MAX_W, B_Y0, B_ROW, B_H = 232.0, 436.0, 16.0, 25.0, 19.0

# --- panel 2: log-log scatter -------------------------------------------
# 622px spans exactly six decades, from the '0' tick at 122 to '1M' at 744
D_X0, D_PX_DEC = 122.0, 622.0 / 6
D_Y0, D_PY_DEC = 848.0, 110.0         # y = D_Y0 - D_PY_DEC * log10(cost each)

# --- panel 3: range + box + median dot ----------------------------------
S_X, S_PX_DEC = 236.0, 136.0          # x = S_X + S_PX_DEC * (log10(v) - 2)
S_Y0, S_ROW = 45.3, 30.6

bx = lambda v, mx: B_MAX_W * v / mx
dx = lambda n: D_X0 + D_PX_DEC * math.log10(n)
dy = lambda c: D_Y0 - D_PY_DEC * math.log10(c)
sx = lambda v: S_X + S_PX_DEC * (math.log10(v) - 2)


def money(v):
    if v >= 1e9:
        return '${:,.1f}B'.format(v / 1e9)
    return '${:,.0f}M'.format(v / 1e6)


def load_spend():
    with open(SPEND) as fh:
        rows = [{
            'name':   r['Condition'],
            'billed': float(r['Total billed']),
            'people': int(r['People affected'].replace(',', '')),
            'each':   float(r['Cost per person']),
        } for r in csv.DictReader(fh)]
    rows.sort(key=lambda r: -r['billed'])
    return rows


def load_var():
    with open(VAR) as fh:
        return {r['Condition']: {
            'median': float(r['Median Cost per Claim']),
            'p25':    float(r['P25 Cost per Claim']),
            'p75':    float(r['P75 Cost per Claim']),
            'lo':     float(r['Min']),
            'hi':     float(r['Max']),
            'rcv':    float(r['Robust CV (IQR/median)']),
        } for r in csv.DictReader(fh)}


def panel_bars(rows):
    top = rows[:TOP_N]
    mx = top[0]['billed']
    head = ('<div class="figure"><svg viewBox="0 0 760 560" role="img" '
            'aria-label="Top 20 conditions by total billed">'
            '<text x="450.0" y="552.0" class="axis-title">total billed, 2020-2024</text>')
    o = []
    for i, r in enumerate(top):
        y = B_Y0 + B_ROW * i
        w = bx(r['billed'], mx)
        cls = 'bar hi' if i == 0 else 'bar'
        o.append('<rect x="{:.1f}" y="{:.1f}" width="{:.1f}" height="{:.1f}" rx="4" '
                 'class="{}"/>'.format(B_X, y, w, B_H, cls))
        o.append('<text x="{:.1f}" y="{:.1f}" class="cat">{}</text>'
                 .format(B_X - 10, y + 13.5, NAME_BAR[r['name']]))
        o.append('<text x="{:.1f}" y="{:.1f}" class="val">{}</text>'
                 .format(B_X + w + 8, y + 13.5, money(r['billed'])))
    # $10B gridlines, emitted last so they draw over the bars
    for b in range(0, 31, 10):
        x = B_X + bx(b * 1e9, mx)
        o.append('<line x1="{:.1f}" y1="16.0" x2="{:.1f}" y2="516.0" class="grid"/>'
                 .format(x, x))
        o.append('<text x="{:.1f}" y="536.0" class="tick tick-x">${}B</text>'.format(x, b))
    return head + '\n'.join(o) + '</svg></div>'


def panel_dots(rows):
    o = [DOTS_HEAD]
    for r in rows[:TOP_N]:
        nm = NAME_DOT[r['name']]
        cls = 'dot sev' if nm in HOSPITAL_ONLY else 'dot'
        o.append('<circle cx="{:.1f}" cy="{:.1f}" r="7" class="{}"><title>{}\n'
                 '{:,} patients | ${:,.0f} per patient</title></circle>'
                 .format(dx(r['people']), dy(r['each']), cls, nm, r['people'], r['each']))
    for nm, x, y, anchor in DOT_LABELS:
        o.append('<text x="{}" y="{}" class="pt" text-anchor="{}">{}</text>'
                 .format(x, y, anchor, nm))
    o.append('<text class="axis-title" transform="translate(30 298.0) rotate(-90)">'
             'cost per patient (log)</text>')
    return ''.join(o) + DOTS_TAIL + '</svg></div>'


def panel_spread(rows, var):
    # only the single widest spread is called out; the next one down is close
    # behind (0.96 against 0.97) and highlighting both would blunt the point
    widest = max(rows[:SPREAD_N], key=lambda r: var[r['name']]['rcv'])['name']
    o = [SPREAD_HEAD]
    for i, r in enumerate(rows[:SPREAD_N]):
        v = var[r['name']]
        y = S_Y0 + S_ROW * i
        x_lo, x_hi = sx(v['lo']), sx(v['hi'])
        b_lo, b_hi = sx(v['p25']), sx(v['p75'])
        hi = ' hi' if r['name'] == widest else ''
        o.append('<line x1="{:.1f}" y1="{:.1f}" x2="{:.1f}" y2="{:.1f}" class="rng{}"/>'
                 .format(x_lo, y, x_hi, y, hi))
        o.append('<rect x="{:.1f}" y="{:.1f}" width="{:.1f}" height="10" rx="3" class="iqr{}"/>'
                 .format(b_lo, y - 5, b_hi - b_lo, hi))
        o.append('<circle cx="{:.1f}" cy="{:.1f}" r="5" class="medot{}"/>'
                 .format(sx(v['median']), y, hi))
        o.append('<text x="224.0" y="{:.1f}" class="cat{}">{}. {}</text>'
                 .format(y + 4, ' vary' if hi else '', i + 1, NAME_SPREAD[r['name']]))
        o.append('<text x="682.0" y="{:.1f}" class="mval{}">{:.2f}</text>'
                 .format(y + 4, hi, v['rcv']))
    o.append('<text x="452.0" y="382.0" class="axis-title">cost per claim (log)</text>')
    return ''.join(o) + '</svg></div>'


def build():
    rows, var = load_spend(), load_var()
    return '\n'.join([
        '<title>Where the Money Goes</title>', STYLE, '<div class="wrap">',
        '<h1>Where the money goes</h1>', LEDE, '', '<section>', H2_1, SUB_1,
        panel_bars(rows), TAKE_1, '</section>', '', '<section>', H2_2, SUB_2,
        panel_dots(rows), KEY_2, TAKE_2, NOTE_2, '</section>', '', '<section>', H2_3, SUB_3,
        panel_spread(rows, var), KEY_3, NOTE_3, TAKE_3, NOTE_3B, '</section>', '</div>',
    ]) + '\n'


NAME_BAR = {'Normal pregnancy': 'Normal pregnancy', 'Allergy to substance (finding)': 'Allergy to substance', 'Gingivitis (disorder)': 'Gingivitis', 'Chronic kidney disease stage 4 (disorder)': 'Chronic kidney disease st.4', 'Non-small cell carcinoma of lung  TNM stage 1 (disorder)': 'Non-small cell lung carcinoma', 'Polyp of colon': 'Polyp of colon', 'Malignant neoplasm of breast (disorder)': 'Malignant neoplasm of breast', 'End-stage renal disease (disorder)': 'End-stage renal disease', 'Gingival disease (disorder)': 'Gingival disease', 'COVID-19': 'COVID-19', 'Laceration - injury (disorder)': 'Laceration - injury', 'Abnormal findings diagnostic imaging heart+coronary circulat (finding)': 'Abnormal cardiac imaging', 'Primary small cell malignant neoplasm of lung  TNM stage 1 (disorder)': 'Small cell lung neoplasm', 'Primary dental caries (disorder)': 'Primary dental caries', 'Child attention deficit disorder': 'Child attention deficit disord', 'Ischemic heart disease (disorder)': 'Ischemic heart disease', 'Dependent drug abuse (disorder)': 'Dependent drug abuse', 'Acute bronchitis (disorder)': 'Acute bronchitis', 'Stroke': 'Stroke', 'Acute infective cystitis (disorder)': 'Acute infective cystitis'}

NAME_DOT = {'Normal pregnancy': 'Normal pregnancy', 'Allergy to substance (finding)': 'Allergy to substance', 'Gingivitis (disorder)': 'Gingivitis', 'Chronic kidney disease stage 4 (disorder)': 'Chronic kidney disease', 'Non-small cell carcinoma of lung  TNM stage 1 (disorder)': 'Non-small cell lung cancer', 'Polyp of colon': 'Polyp of colon', 'Malignant neoplasm of breast (disorder)': 'Malignant neoplasm of breast', 'End-stage renal disease (disorder)': 'End-stage renal disease', 'Gingival disease (disorder)': 'Gingival disease', 'COVID-19': 'COVID-19', 'Laceration - injury (disorder)': 'Laceration - injury', 'Abnormal findings diagnostic imaging heart+coronary circulat (finding)': 'Abnormal findings diagnostic imaging heart+coronary circulat', 'Primary small cell malignant neoplasm of lung  TNM stage 1 (disorder)': 'Small cell lung cancer', 'Primary dental caries (disorder)': 'Primary dental caries', 'Child attention deficit disorder': 'Child attention deficit disorder', 'Ischemic heart disease (disorder)': 'Ischemic heart disease', 'Dependent drug abuse (disorder)': 'Dependent drug abuse', 'Acute bronchitis (disorder)': 'Acute bronchitis', 'Stroke': 'Stroke', 'Acute infective cystitis (disorder)': 'Acute infective cystitis'}

NAME_SPREAD = {'Normal pregnancy': 'Normal pregnancy', 'Allergy to substance (finding)': 'Allergy to substance', 'Gingivitis (disorder)': 'Gingivitis', 'Chronic kidney disease stage 4 (disorder)': 'Chronic kidney disease', 'Non-small cell carcinoma of lung  TNM stage 1 (disorder)': 'Non-small cell lung cancer', 'Polyp of colon': 'Polyp of colon', 'Malignant neoplasm of breast (disorder)': 'Malignant neoplasm of breast', 'End-stage renal disease (disorder)': 'End-stage renal disease', 'Gingival disease (disorder)': 'Gingival disease', 'COVID-19': 'COVID-19'}

HOSPITAL_ONLY = ['COVID-19', 'Non-small cell lung cancer', 'Small cell lung cancer']

DOT_LABELS = [('Normal pregnancy', '666.4', '260.0', 'middle'), ('Gingivitis', '734.0', '424.9', 'middle'), ('Chronic kidney disease', '584.6', '276.9', 'end'), ('Non-small cell lung cancer', '485.1', '175.4', 'start'), ('Small cell lung cancer', '381.7', '155.9', 'end'), ('Acute bronchitis', '672.3', '485.1', 'end'), ('Stroke', '463.0', '268.0', 'end')]

STYLE = '''<style>
:root{--surface-1:#fcfcfb;--surface-2:#f4f3f0;--text-primary:#0b0b0b;--text-secondary:#52514e;
--text-muted:#78766f;--grid:#e6e5e1;--s1:#2a78d6;--s2:#eb6834;--s3:#1baf7a;--iqr:#9ec5f4;--bar-hi:#184f95;--bar-mute:#a9b4c2;}
@media (prefers-color-scheme:dark){:root:not([data-theme="light"]){--surface-1:#1a1a19;--surface-2:#232322;
--text-primary:#fff;--text-secondary:#c3c2b7;--text-muted:#9a988f;--grid:#33322f;
--s1:#3987e5;--s2:#d95926;--s3:#199e70;--iqr:#1c5cab;--bar-hi:#5598e7;--bar-mute:#5c6672;}}
:root[data-theme="dark"]{--surface-1:#1a1a19;--surface-2:#232322;--text-primary:#fff;--text-secondary:#c3c2b7;
--text-muted:#9a988f;--grid:#33322f;--s1:#3987e5;--s2:#d95926;--s3:#199e70;--iqr:#1c5cab;--bar-hi:#5598e7;--bar-mute:#5c6672;}
*{box-sizing:border-box}
body{background:var(--surface-1);color:var(--text-primary);margin:0;padding:32px 20px 48px;
font:15px/1.55 ui-sans-serif,-apple-system,"Segoe UI",system-ui,sans-serif;}
.wrap{max-width:820px;margin:0 auto;}
h1{font-size:23px;margin:0 0 6px;letter-spacing:-.02em;}
.lede{color:var(--text-secondary);font-size:14px;margin:0 0 34px;}
section{margin:0 0 44px;}
h2{font-size:17px;margin:0 0 4px;letter-spacing:-.01em;}
.sub{color:var(--text-secondary);font-size:13.5px;margin:0 0 16px;}
.figure{overflow-x:auto;background:var(--surface-2);border-radius:10px;padding:14px 10px;}
svg{display:block;width:100%;height:auto;min-width:660px;}
.grid{stroke:var(--grid);stroke-width:1;}
.bar{fill:var(--bar-mute);}
.bar.hi{fill:var(--bar-hi);}
.tick{fill:var(--text-muted);font-size:11.5px;}
.tick-x{text-anchor:middle;} .tick-y{text-anchor:end;}
.cat{fill:var(--text-primary);font-size:12px;text-anchor:end;}
.val{fill:var(--text-secondary);font-size:11.5px;}
.axis-title{fill:var(--text-secondary);font-size:12px;text-anchor:middle;}
.dot{fill:var(--bar-mute);stroke:var(--surface-2);stroke-width:2;}
.dot.sev{fill:var(--bar-hi);}
.qline{stroke:var(--grid);stroke-width:1;stroke-dasharray:3 5;}
.axis{stroke:var(--grid);stroke-width:1.25;}
.ticker{stroke:var(--grid);stroke-width:1;}
.arw{stroke:var(--text-muted);stroke-width:1.2;fill:none;opacity:.7;}
.ahd{fill:var(--text-muted);opacity:.7;}
.qt{fill:var(--text-secondary);font-size:12px;font-weight:600;}
.qs{fill:var(--text-muted);font-size:11px;}
.pt{fill:var(--text-primary);font-size:11px;text-anchor:middle;}
.rng{stroke:var(--text-muted);stroke-width:1.5;opacity:.45;}
.rng.hi{stroke:var(--bar-hi);opacity:.85;stroke-width:2;}
.iqr.hi{fill:var(--bar-hi);}
.medot.hi{fill:var(--bar-hi);}
.cat.vary{font-style:italic;fill:var(--bar-hi);font-weight:600;}
.ln{display:inline-block;width:16px;height:0;border-top:1.5px solid var(--text-muted);}
.iqr{fill:var(--iqr);}
.medot{fill:var(--s1);stroke:var(--surface-2);stroke-width:2;}
.key{display:flex;gap:18px;flex-wrap:wrap;margin:12px 0 0;font-size:12.5px;color:var(--text-secondary);}
.key span{display:flex;align-items:center;gap:7px;}
.sw{width:11px;height:11px;border-radius:3px;display:inline-block;}
.note{color:var(--text-muted);font-size:12.5px;margin:14px 0 0;}
.fine{font-size:12.5px;font-style:italic;}
.mval{fill:var(--text-muted);font-size:11.5px;}
.mval.hi{fill:var(--bar-hi);font-weight:700;}
.colhd{fill:var(--text-secondary);font-size:10.5px;letter-spacing:.04em;text-transform:uppercase;}
.take{background:var(--surface-2);border-left:3px solid var(--s1);padding:11px 15px;border-radius:0 7px 7px 0;
margin:14px 0 0;font-size:13.5px;color:var(--text-primary);}
</style>'''

LEDE = '''<p class="lede">Synthea healthcare claims, 2020&ndash;2024. $99.1&nbsp;billion billed across 68.6&nbsp;million claims;
$72.7&nbsp;billion of it attributable to a clinical condition.</p>'''

H2_1 = '''<h2>1. Twenty conditions account for 91% of it</h2>'''

SUB_1 = '''<p class="sub">Total billed per condition. The top 20 cover 90.8% of condition-attributable spend and 66.6% of all spend.</p>'''

TAKE_1 = '''<div class="take">Normal pregnancy alone is <strong>39.8%</strong> &mdash; more than the next three combined.</div>'''

H2_2 = '''<h2>2. High-cost conditions are driven by either volume or treatment intensity</h2>'''

SUB_2 = '''<p class="sub">Each dot is one of the top 20 conditions, placed by how many patients it affects and what it costs to
treat each one. The two extremes sit in opposite corners.</p>'''

DOTS_TAIL = '''<text x="433.0" y="600.0" class="axis-title">number of patients treated (log)</text><line x1="313.5" y1="34.0" x2="552.5" y2="34.0" class="arw" marker-start="url(#ah2)" marker-end="url(#ah)"/><line x1="313.5" y1="566.0" x2="552.5" y2="566.0" class="arw" marker-start="url(#ah2)" marker-end="url(#ah)"/>'''

NOTE_2 = '''<p class="note">Log scales are used because patient counts and costs vary by several orders of magnitude.
Dark blue conditions are recorded almost only on hospital stays, so their patient counts cover the sickest cases
rather than everyone who had the illness.</p>'''

KEY_2 = '''<div class="key">
  <span><i class="sw" style="background:var(--bar-hi)"></i>counted only for hospitalised patients</span>
  <span><i class="sw" style="background:var(--bar-mute)"></i>counted for everyone with the condition</span>
</div>'''

TAKE_2 = '''<div class="take">Gingivitis and lung cancer bill nearly the same in total, from opposite corners:
<strong>800,475 patients at $10,661 each</strong> versus <strong>2,384 patients at $1,416,145 each</strong>.</div>'''

H2_3 = '''<h2>3. Among the biggest-spend conditions, only two vary much between hospitals</h2>'''

SUB_3 = '''<p class="sub">Cost per claim across hospitals for the ten highest-spend conditions. The
<strong>variation</strong> score on the right measures how much ordinary hospitals differ: the price gap between
the cheapest and dearest quarter of hospitals, as a share of the typical price.</p>'''

KEY_3 = '''<div class="key">
  <span><i class="ln"></i>thin line &mdash; full range of hospital prices</span>
  <span><i class="sw" style="background:var(--iqr)"></i>bar &mdash; the middle 50% of hospitals</span>
  <span><i class="sw" style="background:var(--s1);border-radius:50%"></i>dot &mdash; the typical (median) hospital</span>
</div>'''

NOTE_3B = '''<p class="note">Payer type was tested and made almost no difference &mdash; spread across Government, Commercial
and Self-Pay is about 6%. This dataset has no negotiated rates, so the same service is billed identically whoever
pays; payers differ in what share they <em>cover</em>, not what they are charged.</p>'''

NOTE_3 = '''<p class="note fine">Conditions are listed in spend order (1 = largest). Log scale. Hospitals need &ge;30 claims
for a condition to be included.</p>'''

TAKE_3 = '''<div class="take">A score near <strong>0.20</strong> means hospitals charge almost the same. Only breast cancer
(0.97) and normal pregnancy (0.96) approach 1.0; the long thin lines elsewhere are single outlier sites, not
widespread price differences.</div>'''

DOTS_HEAD = '''<div class="figure"><svg viewBox="0 0 800 640" role="img" aria-label="Patients treated against cost per patient, four quadrants"><defs><marker id="ah2" viewBox="0 0 8 8" refX="2" refY="4" markerWidth="6" markerHeight="6" orient="auto"><path d="M8,1 L2,4 L8,7 z" class="ahd"/></marker><marker id="ah" viewBox="0 0 8 8" refX="6" refY="4" markerWidth="6" markerHeight="6" orient="auto"><path d="M0,1 L6,4 L0,7 z" class="ahd"/></marker></defs><line x1="122.0" y1="518.0" x2="744.0" y2="518.0" class="axis"/><line x1="122.0" y1="78.0" x2="122.0" y2="518.0" class="axis"/><line x1="122.0" y1="518.0" x2="122.0" y2="523.0" class="ticker"/><text x="122.0" y="539.0" class="tick tick-x">0</text><line x1="225.7" y1="518.0" x2="225.7" y2="523.0" class="ticker"/><text x="225.7" y="539.0" class="tick tick-x">10</text><line x1="329.3" y1="518.0" x2="329.3" y2="523.0" class="ticker"/><text x="329.3" y="539.0" class="tick tick-x">100</text><line x1="433.0" y1="518.0" x2="433.0" y2="523.0" class="ticker"/><text x="433.0" y="539.0" class="tick tick-x">1K</text><line x1="536.7" y1="518.0" x2="536.7" y2="523.0" class="ticker"/><text x="536.7" y="539.0" class="tick tick-x">10K</text><line x1="640.3" y1="518.0" x2="640.3" y2="523.0" class="ticker"/><text x="640.3" y="539.0" class="tick tick-x">100K</text><line x1="744.0" y1="518.0" x2="744.0" y2="523.0" class="ticker"/><text x="744.0" y="539.0" class="tick tick-x">1M</text><line x1="117.0" y1="518.0" x2="122.0" y2="518.0" class="ticker"/><text x="111.0" y="522.0" class="tick tick-y">0</text><line x1="117.0" y1="408.0" x2="122.0" y2="408.0" class="ticker"/><text x="111.0" y="412.0" class="tick tick-y">$10K</text><line x1="117.0" y1="298.0" x2="122.0" y2="298.0" class="ticker"/><text x="111.0" y="302.0" class="tick tick-y">$100K</text><line x1="117.0" y1="188.0" x2="122.0" y2="188.0" class="ticker"/><text x="111.0" y="192.0" class="tick tick-y">$1M</text><line x1="117.0" y1="78.0" x2="122.0" y2="78.0" class="ticker"/><text x="111.0" y="82.0" class="tick tick-y">$10M</text><line x1="433.0" y1="78.0" x2="433.0" y2="518.0" class="qline"/><line x1="122.0" y1="298.0" x2="744.0" y2="298.0" class="qline"/><text x="203.5" y="38.0" class="qt" text-anchor="middle">Intensity-driven</text><text x="203.5" y="52.0" class="qs" text-anchor="middle">few patients, high cost each</text><text x="662.5" y="38.0" class="qt" text-anchor="middle">High priority</text><text x="662.5" y="52.0" class="qs" text-anchor="middle">many patients, high cost each</text><text x="203.5" y="570.0" class="qt" text-anchor="middle">Lower impact</text><text x="203.5" y="584.0" class="qs" text-anchor="middle">few patients, low cost each</text><text x="662.5" y="570.0" class="qt" text-anchor="middle">Volume-driven</text><text x="662.5" y="584.0" class="qs" text-anchor="middle">many patients, low cost each</text>'''

SPREAD_HEAD = '''<div class="figure"><svg viewBox="0 0 780 400" role="img" aria-label="Cost per claim across hospitals for the ten highest-spend conditions, with a variation score"><line x1="236.0" y1="336.0" x2="668.0" y2="336.0" class="axis"/><text x="682.0" y="20.0" class="colhd">variation</text><line x1="236.0" y1="336.0" x2="236.0" y2="341.0" class="ticker"/><text x="236.0" y="357.0" class="tick tick-x">$100</text><line x1="372.0" y1="336.0" x2="372.0" y2="341.0" class="ticker"/><text x="372.0" y="357.0" class="tick tick-x">$1,000</text><line x1="508.0" y1="336.0" x2="508.0" y2="341.0" class="ticker"/><text x="508.0" y="357.0" class="tick tick-x">$10,000</text><line x1="644.0" y1="336.0" x2="644.0" y2="341.0" class="ticker"/><text x="644.0" y="357.0" class="tick tick-x">$100,000</text>'''


if __name__ == '__main__':
    open(OUT, 'w').write(build())
    print('wrote', OUT)
