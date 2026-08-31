#!/usr/bin/env python3
"""Generate dashboard/q2_same_condition_different_insurance.html from
sql/results/q2_share_by_payer_type_yearly_2020_2024.csv.

    python3 dashboard/generators/q2_same_condition_different_insurance.py

Written 2026-08-29 to replace a generator lost with a session scratch directory.

READS THE YEARLY FILE, NOT THE POOLED ONE, and the difference is the point. Each
dot is the MEDIAN OF FIVE ANNUAL FIGURES, so the tooltip can show the range and
a reader can see the gap is stable rather than a one-year artefact. The pooled
per-condition file (q2_top10_share_by_payer_type) gives slightly different
numbers -- Government 58.2 against 57.8 for the first row -- because pooling
weights years by volume. Do not swap the sources to make them agree; they answer
different questions.

Only Commercial and Government are plotted. Uninsured sit at exactly 100% for
every condition, which is true but carries no information and would stretch the
axis; "Everyone" is a blend of the three and belongs to a different question.
"""
import csv, os

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
SRC  = os.path.join(ROOT, 'sql/results/q2_share_by_payer_type_yearly_2020_2024.csv')
OUT  = os.path.join(ROOT, 'dashboard/q2_same_condition_different_insurance.html')

X0, X100 = 250.0, 670.0          # 0% and 100% on the shared axis
ROW0, ROW_H = 107.0, 30.0        # first row centre, then one row per condition
BAND_X, BAND_W = 250, 420
CAT_X, GAP_X = 237, 696

sx = lambda pct: X0 + (X100 - X0) * pct / 100.0

# short display names; the source spells conditions out in full
SHORTEN = {
    'Concussion with loss of consciousness':    'Concussion with loss of consciousness',
    'Concussion with no loss of consciousness': 'Concussion, no loss of consciousness',
    'Prediabetes (finding)':                    'Prediabetes',
    'Concussion injury of brain (disorder)':    'Concussion injury of brain',
    'Otitis media':                             'Otitis media',
    'Asthma':                                   'Asthma',
    'Body mass index 30+ - obesity (finding)':  'Obesity (BMI 30+)',
    'Sprain (morphologic abnormality)':         'Sprain',
    'Fracture subluxation of wrist':            'Fracture subluxation of wrist',
    'Fracture of clavicle':                     'Fracture of clavicle',
}


def load():
    rows = {}
    order = []
    with open(SRC) as fh:
        for r in csv.DictReader(fh):
            cond, kind = r['Condition'], r['Kind of insurance']
            if kind not in ('Commercial', 'Government'):
                continue
            if cond not in rows:
                rows[cond] = {}
                order.append(cond)
            rows[cond][kind] = {
                'pct': float(r['Typical % of the bill the patient pays']),
                'lo':  float(r['Lowest year']),
                'hi':  float(r['Highest year']),
            }
    return [(c, rows[c]) for c in order]


def build():
    data = load()
    o = ['<title>The Insurance Gap</title>', STYLE, '<div class="wrap">',
         '<h1>Which insurer you have matters more than which condition you have</h1>',
         LEDE, '', H2, SUB,
         '<div class="figure"><svg viewBox="0 0 760 436" xmlns="http://www.w3.org/2000/svg" '
         'role="img" aria-label="Median share of the bill paid by patients, by condition '
         'and kind of insurance">',
         '<text x="696" y="34" class="colhd" text-anchor="start">Gap</text>']

    for pct in (0, 25, 50, 75, 100):
        x = sx(pct)
        o.append('<line class="grid" x1="{:.1f}" y1="62" x2="{:.1f}" y2="398"/>'.format(x, x))
        o.append('<text x="{:.1f}" y="56" class="tick tick-x">{}%</text>'.format(x, pct))

    for i, (cond, d) in enumerate(data):
        y = ROW0 + ROW_H * i
        g, c = d['Government'], d['Commercial']
        gx, cx = sx(g['pct']), sx(c['pct'])
        if i % 2 == 0:      # zebra banding, on the even rows
            o.append('<rect class="band" x="{}" y="{:.1f}" width="{}" height="{:.0f}"/>'
                     .format(BAND_X, y - ROW_H / 2, BAND_W, ROW_H))
        o.append('<line class="conn" x1="{:.1f}" y1="{:.1f}" x2="{:.1f}" y2="{:.1f}"/>'
                 .format(gx, y, cx, y))
        for kind, dd, x in (('govt', g, gx), ('comm', c, cx)):
            label = 'Government' if kind == 'govt' else 'Commercial'
            o.append('<circle class="dot {}" cx="{:.1f}" cy="{:.1f}" r="5.5"><title>{}: {}% '
                     '(range {}-{} across 2020-2024)</title></circle>'
                     .format(kind, x, y, label, fmt(dd['pct']), fmt(dd['lo']), fmt(dd['hi'])))
        o.append('<text x="{}" y="{:.1f}" class="cat">{}</text>'
                 .format(CAT_X, y + 4, SHORTEN.get(cond, cond)))
        o.append('<text x="{}" y="{:.1f}" class="mval">+{:.0f} pts</text>'
                 .format(GAP_X, y + 4, c['pct'] - g['pct']))
        if i == 0:      # name the two dots once, on the top row only
            o.append('<text x="{:.1f}" y="{:.1f}" class="mk govt e">Government</text>'
                     .format(gx - 9, y - 11))
            o.append('<text x="{:.1f}" y="{:.1f}" class="mk comm s">Commercial</text>'
                     .format(cx + 9, y - 11))

    o.append('<text x="460" y="424" class="axis-title">Typical share of the bill the '
             'patient pays: median of the five years 2020&#8211;2024</text>')
    o.append('</svg></div>')
    o.append(TAIL)
    o.append('</div>')
    return '\n'.join(o) + '\n'


def fmt(v):
    return '{:.1f}'.format(v)


STYLE = '''<style>
:root{--surface-1:#fcfcfb;--surface-2:#f4f3f0;--text-primary:#0b0b0b;--text-secondary:#52514e;
--text-muted:#78766f;--grid:#e6e5e1;--comm:#eb6834;--govt:#2a78d6;--self:#1baf7a;--band:#ecebe7;--conn:#b9b8b2;}
@media (prefers-color-scheme:dark){:root:not([data-theme="light"]){--surface-1:#1a1a19;--surface-2:#232322;
--text-primary:#fff;--text-secondary:#c3c2b7;--text-muted:#9a988f;--grid:#33322f;
--comm:#e8712f;--govt:#3987e5;--self:#19a56f;--band:#2b2b29;--conn:#57574f;}}
:root[data-theme="dark"]{--surface-1:#1a1a19;--surface-2:#232322;--text-primary:#fff;--text-secondary:#c3c2b7;
--text-muted:#9a988f;--grid:#33322f;--comm:#e8712f;--govt:#3987e5;--self:#19a56f;--band:#2b2b29;--conn:#57574f;}
*{box-sizing:border-box}
body{background:var(--surface-1);color:var(--text-primary);margin:0;padding:32px 20px 48px;
font:15px/1.55 ui-sans-serif,-apple-system,"Segoe UI",system-ui,sans-serif;}
.wrap{max-width:790px;margin:0 auto;}
h1{font-size:23px;margin:0 0 6px;letter-spacing:-.02em;}
.lede{color:var(--text-secondary);font-size:14px;margin:0 0 26px;}
h2{font-size:17px;margin:0 0 4px;letter-spacing:-.01em;}
.sub{color:var(--text-secondary);font-size:13.5px;margin:0 0 16px;}
.figure{overflow-x:auto;background:var(--surface-2);border-radius:10px;padding:16px 12px 10px;}
svg{display:block;width:100%;height:auto;min-width:660px;}
.grid{stroke:var(--grid);stroke-width:1;}
.band{fill:var(--band);}
.tick{fill:var(--text-muted);font-size:11px;} .tick-x{text-anchor:middle;}
.cat{fill:var(--text-primary);font-size:12px;text-anchor:end;}
.conn{stroke:var(--conn);stroke-width:2.5;}
.blend{stroke:var(--text-muted);stroke-width:1.6;stroke-dasharray:2 2;}
.dot{stroke:var(--surface-2);stroke-width:1.5;}
.dot.comm{fill:var(--comm);} .dot.govt{fill:var(--govt);} .dot.self{fill:var(--self);}
.mk{font-size:10px;font-weight:700;text-anchor:middle;}
.mk.e{text-anchor:end;} .mk.s{text-anchor:start;}
.mk.comm{fill:var(--comm);} .mk.govt{fill:var(--govt);} .mk.self{fill:var(--self);}
.mval{fill:var(--text-muted);font-size:11px;text-anchor:start;}
.colhd{fill:var(--text-secondary);font-size:10px;letter-spacing:.05em;text-transform:uppercase;}
.axis-title{fill:var(--text-secondary);font-size:11.5px;text-anchor:middle;}
.note{color:var(--text-muted);font-size:12.5px;margin:16px 0 0;}
.lims{color:var(--text-muted);font-size:12.5px;margin:5px 0 0;padding-left:18px;}
.lims li{margin:2px 0;}
.take{background:var(--surface-2);border-left:3px solid var(--comm);padding:11px 15px;border-radius:0 7px 7px 0;
margin:18px 0 0;font-size:13.5px;color:var(--text-primary);}
</style>'''

LEDE = '''<p class="lede">Synthea healthcare claims, 2020&ndash;2024. The ten conditions where patients carry the
largest share of the bill, each split by kind of insurance. At least 5,000 people affected per
condition.</p>'''

H2 = '''<h2>Prediabetes costs a commercial patient 85.0% of the bill and a government patient 8.5% &mdash; same care</h2>'''

SUB = '''<p class="sub">Each dot is the typical share for one kind of insurance &mdash; the median of the five
annual figures, not the five years pooled. The line between them is the gap.</p>'''

TAIL = '''<div class="take"><strong>The blended figure is one almost nobody pays.</strong> Prediabetes reads 62.2%
overall, but a commercially insured patient pays <strong>85.0%</strong> and a government-covered
patient <strong>8.5%</strong> &mdash; ten times the share for the same care. Obesity is wider still,
86.8% against 8.7%. Both are chronic-risk conditions managed through routine screening and
counselling, which is exactly the cheap-visit territory where a flat copay absorbs most of the bill.</div>

<p class="note"><strong>Limitations</strong></p>
<ul class="lims">
<li>Uninsured are excluded &mdash; they pay 100% of every condition, by construction.</li>
<li>Gap is commercial minus government, in percentage points.</li>
<li>Medians move little: no condition varies by more than 6.1 points across the five years.</li>
<li>The gap between insurers beats the whole spread across these ten conditions &mdash; which runs just 54.3% to 67.9% &mdash; on 9 of the 10.</li>
<li>Share, not money &mdash; concussion is 67.9% of a $98 claim, or $123 a person.</li>
<li>Conditions ranked by the pooled blend, so row order is not the median order.</li>
</ul>

<p class="note">Source: <code>sql/analysis/q2_share_by_payer_type_yearly.sql</code> &middot;
<code>sql/results/q2_share_by_payer_type_yearly_2020_2024.csv</code></p>'''

if __name__ == '__main__':
    open(OUT, 'w').write(build())
    print('wrote', OUT)
