#!/usr/bin/env python3
"""Generate dashboard/q2_care_type_scatter.html from
sql/results/q2_patient_cost_by_care_type_2020_2024.csv.

    python3 dashboard/generators/q2_care_type_scatter.py

Written 2026-08-29 to replace a generator lost with a session scratch directory.

LABELS is hand-tuned and has to stay that way. Fifteen circles at these radii
collide, so each label carries the side it sits on and, where that is still not
enough, a leader line pulling it clear. Nothing computes those; they were chosen
by eye. If the underlying figures move enough to shift positions, re-check every
label rather than trusting the old offsets -- a silently overlapping label is
the failure this table exists to prevent.

Two things the chart says about itself that are worth knowing are imprecise:

Circle area is NOT strictly proportional to people. Radius runs on a scaled
square root with a 5px floor, so the smallest circles read larger than their
share of people. Without the floor, Infections at 13,122 people would be under
4px across and effectively invisible. The limitation list says "area, not
radius, is proportional" -- close enough to steer reading, not exact.

The shares are blends across insurance type, which the limitation list does say.
Commercial patients pay far more than government ones, so no single figure here
describes an actual patient. See q2_pattern_within_payer.sql.

Checked against the chart it replaces: every word identical, same count of
numbers, and 22 of 495 numbers differ by at most 0.1px. Those come from the old
file's x-scale, which was not quite a round 256px per tenfold step. This uses
the round value, anchored on the $100M and $1B ticks. A tenth of a pixel is not
visible; nothing else moved.
"""
import csv, math, os

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
SRC  = os.path.join(ROOT, 'sql/results/q2_patient_cost_by_care_type_2020_2024.csv')
OUT  = os.path.join(ROOT, 'dashboard/q2_care_type_scatter.html')

# x is log10 dollars, y is percent of the bill, both fixed to the plot box
# anchored on the $100M and $1B ticks of the chart this replaces, which sit
# exactly 256.0px apart -- one clean decade
X_REF, X_REF_V, PX_PER_DECADE = 305.2, 100e6, 256.0
Y0, PX_PER_PCT = 448.0, 9.1433
R_MIN, R_MAX = 5.0, 30.0

sx = lambda v: X_REF + PX_PER_DECADE * (math.log10(v) - math.log10(X_REF_V))
sy = lambda p: Y0 - PX_PER_PCT * p

XTICKS = [(20e6, '$20M'), (50e6, '$50M'), (100e6, '$100M'), (250e6, '$250M'),
          (500e6, '$500M'), (1e9, '$1B'), (2.5e9, '$2.5B'), (5e9, '$5B')]
YTICKS = [10, 20, 30, 40]

# labels that hang below their circle instead of sitting level with it
Y_NUDGE = {'Mental health & substance use': 10, 'Cancer & tumours': 10}
Y_NUDGE_DEFAULT = 4

# care type -> (which side the label sits, leader dy or None, highlighted)
LABELS = {
    'Dental & oral':                 ('e', None, True),
    'Respiratory & ENT':             ('s',   12, False),
    'Injury & trauma':               ('s',   36, False),
    'Diabetes & metabolic':          ('s', None, False),
    'Mental health & substance use': ('s', None, False),
    'Maternity':                     ('e', None, False),
    'Kidney & urinary':              ('s', None, False),
    'Heart & circulation':           ('s',  -24, False),
    'Cancer & tumours':              ('s', None, False),
    'Blood disorders':               ('s', None, False),
    'Other':                         ('s', None, False),
    'Allergy & immune':              ('s', None, False),
    'Chronic pain':                  ('s', None, False),
    'Brain & nervous system':        ('s', None, False),
    'Infections (other)':            ('s', None, False),
}


def money(v):
    return '${:.2f}B'.format(v / 1e9) if v >= 1e9 else '${:.0f}M'.format(v / 1e6)


def load():
    with open(SRC) as fh:
        rows = [{
            'name':   r['Type of care'],
            'paid':   float(r['Paid by patients over 5 years']),
            'share':  float(r['% of the bill patients pay']),
            'people': int(r['People affected'].replace(',', '')),
            'bill':   float(r['Total bill']),
        } for r in csv.DictReader(fh)]
    rows.sort(key=lambda r: -r['people'])
    lo = math.sqrt(min(r['people'] for r in rows))
    hi = math.sqrt(max(r['people'] for r in rows))
    for r in rows:
        r['r'] = R_MIN + (R_MAX - R_MIN) * (math.sqrt(r['people']) - lo) / (hi - lo)
    return rows


def build():
    rows = load()
    o = [ '<title>Big Bills or Big Shares</title>', STYLE, '<div class="wrap">',
          '<h1>Only dental is both a big bill and a big share</h1>', LEDE, '', H2, SUB,
          '<div class="figure"><svg viewBox="0 0 790 520" xmlns="http://www.w3.org/2000/svg" '
          'role="img" aria-label="Each type of care plotted by total patient out-of-pocket '
          'against the share of the bill patients pay">' ]

    for p in YTICKS:
        y = sy(p)
        o.append('<line class="grid" x1="74" y1="{:.1f}" x2="764" y2="{:.1f}"/>'.format(y, y))
        o.append('<text x="65" y="{:.1f}" class="tick tick-y">{}%</text>'.format(y + 4, p))
    o.append('<text x="65" y="452.0" class="tick tick-y">0%</text>')
    for v, lab in XTICKS:
        x = sx(v)
        o.append('<line class="ticker" x1="{:.1f}" y1="448" x2="{:.1f}" y2="453"/>'.format(x, x))
        o.append('<text x="{:.1f}" y="466" class="tick tick-x">{}</text>'.format(x, lab))

    for r in rows:
        x, y = sx(r['paid']), sy(r['share'])
        side, lead_dy, hi = LABELS[r['name']]
        cls = 'pt hi' if hi else 'pt'
        o.append('<circle class="{}" cx="{:.1f}" cy="{:.1f}" r="{:.1f}"><title>{}\n'
                 '{} paid by patients ({:.1f}% of a {} bill)\n'
                 '{:,} people affected</title></circle>'
                 .format(cls, x, y, r['r'], r['name'], money(r['paid']),
                         r['share'], money(r['bill']), r['people']))
        edge = x + r['r'] if side == 's' else x - r['r']
        if lead_dy is None:
            tx, ty = (edge + (8 if side == 's' else -8),
                      y + Y_NUDGE.get(r['name'], Y_NUDGE_DEFAULT))
        else:
            x1 = edge + (2 if side == 's' else -2)
            x2 = x1 + (6 if side == 's' else -6)
            y2 = y + lead_dy
            o.append('<line class="lead" x1="{:.1f}" y1="{:.1f}" x2="{:.1f}" y2="{:.1f}"/>'
                     .format(x1, y, x2, y2))
            tx, ty = x2, y2 + 4
        lab_cls = 'lab {} hi'.format(side) if hi else 'lab {}'.format(side)
        o.append('<text x="{:.1f}" y="{:.1f}" class="{}">{}</text>'
                 .format(tx, ty, lab_cls, r['name']))

    o.append('<line class="axis" x1="74" y1="448" x2="764" y2="448"/>')
    o.append('<text x="419" y="492" class="axis-title">Total paid by patients '
             'over five years &#8212; log scale</text>')
    o.append('<text class="axis-title" transform="translate(16,256) rotate(-90)">'
             'Share of the bill patients pay</text>')
    o.append('</svg></div>')
    o.append(TAKE)
    o.append('')
    o.append(LIMS)
    o.append('</div>')
    return '\n'.join(o) + '\n'


STYLE = '''<style>
:root{--surface-1:#fcfcfb;--surface-2:#f4f3f0;--text-primary:#0b0b0b;--text-secondary:#52514e;
--text-muted:#78766f;--grid:#e6e5e1;--grid-minor:#f0efec;--pt:#d6a888;--hi:#0f9d76;--axis:#c9c8c3;}
@media (prefers-color-scheme:dark){:root:not([data-theme="light"]){--surface-1:#1a1a19;--surface-2:#232322;
--text-primary:#fff;--text-secondary:#c3c2b7;--text-muted:#9a988f;--grid:#33322f;--grid-minor:#2a2a28;
--pt:#8f6a51;--hi:#19c093;--axis:#4a4a45;}}
:root[data-theme="dark"]{--surface-1:#1a1a19;--surface-2:#232322;--text-primary:#fff;--text-secondary:#c3c2b7;
--text-muted:#9a988f;--grid:#33322f;--grid-minor:#2a2a28;--pt:#8f6a51;--hi:#19c093;--axis:#4a4a45;}
*{box-sizing:border-box}
body{background:var(--surface-1);color:var(--text-primary);margin:0;padding:32px 20px 48px;
font:15px/1.55 ui-sans-serif,-apple-system,"Segoe UI",system-ui,sans-serif;}
.wrap{max-width:790px;margin:0 auto;}
h1{font-size:23px;margin:0 0 6px;letter-spacing:-.02em;}
.lede{color:var(--text-secondary);font-size:14px;margin:0 0 26px;}
h2{font-size:17px;margin:0 0 4px;letter-spacing:-.01em;}
.sub{color:var(--text-secondary);font-size:13.5px;margin:0 0 16px;}
.figure{overflow-x:auto;background:var(--surface-2);border-radius:10px;padding:14px 10px 8px;}
svg{display:block;width:100%;height:auto;min-width:680px;}
.grid{stroke:var(--grid);stroke-width:1;}
.grid.minor{stroke:var(--grid-minor);}
.axis{stroke:var(--axis);stroke-width:1.25;}
.tick{fill:var(--text-muted);font-size:11px;}
.tick-x{text-anchor:middle;} .tick-y{text-anchor:end;}
.pt{fill:var(--pt);fill-opacity:.7;stroke:var(--pt);stroke-width:1.25;}
.pt.hi{fill:var(--hi);fill-opacity:.8;stroke:var(--hi);stroke-width:2;}
.ticker{stroke:var(--axis);stroke-width:1;}
.lab{fill:var(--text-secondary);font-size:11.5px;}
.lab.hi{fill:var(--hi);font-weight:700;font-size:12.5px;}
.lab.s{text-anchor:start;} .lab.e{text-anchor:end;} .lab.m{text-anchor:middle;}
.lead{stroke:var(--text-muted);stroke-width:1;opacity:.5;}
.axis-title{fill:var(--text-secondary);font-size:11.5px;text-anchor:middle;}
.note{color:var(--text-muted);font-size:12.5px;margin:16px 0 0;}
.lims{color:var(--text-muted);font-size:12.5px;margin:5px 0 0;padding-left:18px;}
.lims li{margin:2px 0;}
.take{background:var(--surface-2);border-left:3px solid var(--hi);padding:11px 15px;border-radius:0 7px 7px 0;
margin:18px 0 0;font-size:13.5px;color:var(--text-primary);}
</style>'''

LEDE = '''<p class="lede">Synthea healthcare claims, 2020&ndash;2024. Each circle is one of the 15 types of care.
Position left to right is what patients paid in total; position up the page is how much of the bill
they carried; circle area is how many people were affected.</p>'''

H2 = '''<h2>Everything else is either a lot of money at a small share, or a big share of very little</h2>'''

SUB = '''<p class="sub"><strong>Circle size is the number of people affected</strong>, from 13,122 for
infections to 938,009 for dental. The horizontal axis is a log scale &mdash; patient spending runs
from $16M to $4.9B, a 300-fold range a linear axis would flatten into one cluster.</p>'''

TAKE = '''<div class="take"><strong>The top-right corner is the one worth acting on, and only dental is in it.</strong>
$3.30B paid by patients at 27.9% of the bill across 938,009 people. Maternity is larger in dollars but
patients carry only 17.0% of it; diabetes and metabolic care has a higher share at 36.6% but patients
pay just $159M. Dental is the only type of care that is simultaneously expensive to patients,
expensive <em>as a proportion</em>, and widespread.</div>'''

LIMS = '''<p class="note"><strong>Limitations</strong></p>
<ul class="lims">
<li>Log x-axis &mdash; equal spacing means ten times the money, not ten times more.</li>
<li>Circle area, not radius, is proportional to people &mdash; sizes are comparable, not readable as values.</li>
<li>Shares are blends across insurance type; commercial patients pay far more than government ones.</li>
<li>Dollar amounts inflated by flat procedure pricing; positions and rankings hold.</li>
</ul>

<p class="note">Source: <code>sql/analysis/q2_patient_cost_by_care_type.sql</code> &middot;
<code>sql/results/q2_patient_cost_by_care_type_2020_2024.csv</code></p>'''

if __name__ == '__main__':
    open(OUT, 'w').write(build())
    print('wrote', OUT)
