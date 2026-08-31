#!/usr/bin/env python3
"""Generate dashboard/q2_share_vs_cost_per_person.html from
sql/results/q2_patient_cost_by_care_type_2020_2024.csv.

    python3 dashboard/generators/q2_share_vs_cost_per_person.py

Written 2026-08-29 to replace a generator lost with a session scratch directory.

Deliberately standalone, though it shares its y-scale, radius rule and label
logic with q2_care_type_scatter.py. The two plot the same 15 circles against
different x-axes -- what patients paid in total there, cost per person here --
so keeping them apart means either can be retuned without disturbing the other.
If a third chart ever wants the same machinery, factor it out then.

WHAT THIS CHART CLAIMS, AND WHAT LATER WORK FOUND. The headline is that cheaper
care carries a bigger patient share, with two types marked "off" as running
against it. Neither is really an exception:

  Infections only looks dear per person. Its median claim is $1,542 against a
  $5,466 mean, so the typical claim sits far below the annual out-of-pocket
  maximum while a few very large ones lift the average. Cost per person -- this
  chart's x-axis -- mixes claim size with how often someone attends, and only
  claim size interacts with the cap.

  Brain & nervous system is 90.2% government-funded spend, and those patients
  pay a flat $0-50 whatever the bill. Split by payer it reads 40.2% rather than
  8.5%, which is no exception at all.

Both stay marked "off" because this chart plots blended shares, and on that
measure they do sit off the trend. See q2_pattern_breakers.sql. Do not restate
the headline without this caveat.

Checked against the chart it replaces: every word identical, same count of
numbers, and 19 of 489 numbers differ by at most 0.1px -- the old file's x-scale
was not quite a round 314.1px per tenfold step. The trend line is recomputed as
a least-squares fit rather than copied, and lands on the old endpoints exactly.
"""
import csv, math, os

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
SRC  = os.path.join(ROOT, 'sql/results/q2_patient_cost_by_care_type_2020_2024.csv')
OUT  = os.path.join(ROOT, 'dashboard/q2_share_vs_cost_per_person.html')

# anchored on the $10K and $100K ticks of the chart this replaces, exactly
# 314.1px apart -- one tenfold step
X_REF, X_REF_V, PX_PER_DECADE = 342.3, 1e4, 314.1
Y0, PX_PER_PCT = 448.0, 9.1433
R_MIN, R_MAX = 5.0, 30.0

sx = lambda v: X_REF + PX_PER_DECADE * (math.log10(v) - math.log10(X_REF_V))
sy = lambda p: Y0 - PX_PER_PCT * p

# the fitted line's horizontal extent is a layout choice; its height at each end
# is computed from the least-squares fit, not drawn by eye
TREND_X0, TREND_X1 = 80.7, 757.0

XTICKS = [(2e3, '$2K'), (5e3, '$5K'), (1e4, '$10K'), (2.5e4, '$25K'),
          (5e4, '$50K'), (1e5, '$100K'), (2e5, '$200K')]
YTICKS = [10, 20, 30, 40]

# care type -> (side, leader dy or None, greyed as off-trend, y nudge)
# hand-tuned by eye; 15 circles at these radii collide otherwise
LABELS = {
    'Dental & oral':                 ('s',   15, False,  4),
    'Respiratory & ENT':             ('s',  -25, False,  4),
    'Injury & trauma':               ('s',  -50, False,  4),
    'Diabetes & metabolic':          ('s', None, False,  4),
    'Mental health & substance use': ('s', None, False,  4),
    'Maternity':                     ('e', None, False,  4),
    'Kidney & urinary':              ('s', None, False,  4),
    'Heart & circulation':           ('s',  -20, False,  4),
    'Cancer & tumours':              ('e', None, False,  4),
    'Blood disorders':               ('s', None, False,  4),
    'Other':                         ('s', None, False,  4),
    'Allergy & immune':              ('e', None, False, -1),
    'Chronic pain':                  ('s', None, False,  4),
    'Brain & nervous system':        ('s', None, True,   4),
    'Infections (other)':            ('s', None, True,  -1),
}


def fit(rows):
    """Least-squares line of patient share on log10(cost per person).

    This is the chart's claim made visible: 13 of 15 types sit near it. It is
    computed rather than drawn, so it moves honestly if the data moves.
    """
    xs = [math.log10(r['perp']) for r in rows]
    ys = [r['share'] for r in rows]
    n = len(xs)
    mx, my = sum(xs) / n, sum(ys) / n
    b = (sum((xs[i] - mx) * (ys[i] - my) for i in range(n))
         / sum((x - mx) ** 2 for x in xs))
    return my - b * mx, b


def unsx(x):
    return 10 ** (math.log10(X_REF_V) + (x - X_REF) / PX_PER_DECADE)


def money(v):
    return '${:.0f}K'.format(v / 1e3) if v >= 1e4 else '${:.1f}K'.format(v / 1e3)


def load():
    with open(SRC) as fh:
        rows = [{
            'name':   r['Type of care'],
            'perp':   float(r['Total cost per person over 5 years']),
            'share':  float(r['% of the bill patients pay']),
            'people': int(r['People affected'].replace(',', '')),
        } for r in csv.DictReader(fh)]
    rows.sort(key=lambda r: -r['people'])
    lo = math.sqrt(min(r['people'] for r in rows))
    hi = math.sqrt(max(r['people'] for r in rows))
    for r in rows:
        r['r'] = R_MIN + (R_MAX - R_MIN) * (math.sqrt(r['people']) - lo) / (hi - lo)
    return rows


def build():
    rows = load()
    o = ['<title>Cheaper Care, Bigger Share</title>', STYLE, '<div class="wrap">',
         '<h1>The cheaper the care, the more of the bill patients carry</h1>',
         LEDE, '', H2, SUB,
         '<div class="figure"><svg viewBox="0 0 790 520" xmlns="http://www.w3.org/2000/svg" '
         'role="img" aria-label="Patient share of the bill against cost per person, '
         'by type of care">']

    for p in YTICKS:
        y = sy(p)
        o.append('<line class="grid" x1="74" y1="{:.1f}" x2="764" y2="{:.1f}"/>'.format(y, y))
        o.append('<text x="65" y="{:.1f}" class="tick tick-y">{}%</text>'.format(y + 4, p))
    o.append('<text x="65" y="452.0" class="tick tick-y">0%</text>')
    for v, lab in XTICKS:
        x = sx(v)
        o.append('<line class="ticker" x1="{:.1f}" y1="448" x2="{:.1f}" y2="453"/>'.format(x, x))
        o.append('<text x="{:.1f}" y="466" class="tick tick-x">{}</text>'.format(x, lab))

    a, b = fit(rows)
    o.append('<line class="trend" x1="{:.1f}" y1="{:.1f}" x2="{:.1f}" y2="{:.1f}"/>'
             .format(TREND_X0, sy(a + b * math.log10(unsx(TREND_X0))),
                     TREND_X1, sy(a + b * math.log10(unsx(TREND_X1)))))

    for r in rows:
        x, y = sx(r['perp']), sy(r['share'])
        side, lead_dy, off, nudge = LABELS[r['name']]
        o.append('<circle class="pt{}" cx="{:.1f}" cy="{:.1f}" r="{:.1f}"><title>{}\n'
                 '{} per person over five years\n'
                 'patients pay {:.1f}% of it\n'
                 '{:,} people affected</title></circle>'
                 .format(' off' if off else '', x, y, r['r'], r['name'],
                         money(r['perp']), r['share'], r['people']))
        edge = x + r['r'] if side == 's' else x - r['r']
        if lead_dy is None:
            tx, ty = edge + (8 if side == 's' else -8), y + nudge
        else:
            x1 = edge + (2 if side == 's' else -2)
            x2 = x1 + (6 if side == 's' else -6)
            y2 = y + lead_dy
            o.append('<line class="lead" x1="{:.1f}" y1="{:.1f}" x2="{:.1f}" y2="{:.1f}"/>'
                     .format(x1, y, x2, y2))
            tx, ty = x2, y2 + 4
        o.append('<text x="{:.1f}" y="{:.1f}" class="lab {}{}">{}</text>'
                 .format(tx, ty, side, ' off' if off else '', r['name']))

    o.append('<line class="axis" x1="74" y1="448" x2="764" y2="448"/>')
    o.append('<text x="419" y="492" class="axis-title">Total cost per person over five '
             'years, log scale</text>')
    o.append('<text class="axis-title" transform="translate(16,256) rotate(-90)">'
             'Share of the bill patients pay</text>')
    o.append('</svg></div>')
    o.append(TAKE)
    o.append('')
    o.append(TAIL)
    o.append('</div>')
    return '\n'.join(o) + '\n'


STYLE = '''<style>
:root{--surface-1:#fcfcfb;--surface-2:#f4f3f0;--text-primary:#0b0b0b;--text-secondary:#52514e;
--text-muted:#78766f;--grid:#e6e5e1;--pt:#d6a888;--off:#7c5cd6;--axis:#c9c8c3;--trend:#9a988f;}
@media (prefers-color-scheme:dark){:root:not([data-theme="light"]){--surface-1:#1a1a19;--surface-2:#232322;
--text-primary:#fff;--text-secondary:#c3c2b7;--text-muted:#9a988f;--grid:#33322f;
--pt:#8f6a51;--off:#a78bfa;--axis:#4a4a45;--trend:#6f6d66;}}
:root[data-theme="dark"]{--surface-1:#1a1a19;--surface-2:#232322;--text-primary:#fff;--text-secondary:#c3c2b7;
--text-muted:#9a988f;--grid:#33322f;--pt:#8f6a51;--off:#a78bfa;--axis:#4a4a45;--trend:#6f6d66;}
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
.axis{stroke:var(--axis);stroke-width:1.25;}
.ticker{stroke:var(--axis);stroke-width:1;}
.tick{fill:var(--text-muted);font-size:11px;}
.tick-x{text-anchor:middle;} .tick-y{text-anchor:end;}
.trend{stroke:var(--trend);stroke-width:1.5;stroke-dasharray:6 5;}
.trendlab{fill:var(--text-muted);font-size:10.5px;text-anchor:middle;font-style:italic;}
.pt{fill:var(--pt);fill-opacity:.7;stroke:var(--pt);stroke-width:1.25;}
.pt.off{fill:var(--off);fill-opacity:.8;stroke:var(--off);stroke-width:2;}
.lab{fill:var(--text-secondary);font-size:11.5px;}
.lab.off{fill:var(--off);font-weight:700;font-size:12.5px;}
.lab.s{text-anchor:start;} .lab.e{text-anchor:end;} .lab.m{text-anchor:middle;}
.lead{stroke:var(--text-muted);stroke-width:1;opacity:.5;}
.axis-title{fill:var(--text-secondary);font-size:11.5px;text-anchor:middle;}
.note{color:var(--text-muted);font-size:12.5px;margin:16px 0 0;}
.lims{color:var(--text-muted);font-size:12.5px;margin:5px 0 0;padding-left:18px;}
.lims li{margin:2px 0;}
.take{background:var(--surface-2);border-left:3px solid var(--off);padding:11px 15px;border-radius:0 7px 7px 0;
margin:18px 0 0;font-size:13.5px;color:var(--text-primary);}
</style>'''

LEDE = '''<p class="lede">Synthea healthcare claims, 2020&ndash;2024. Each circle is one of the 15 types of care,
placed by what the care costs <em>per person</em> and by how much of that bill the patient pays.
Circle size is the number of people affected.</p>'''

H2 = '''<h2>Thirteen of fifteen types follow the pattern &mdash; two run against it</h2>'''

SUB = '''<p class="sub">The dashed line is a least-squares guide: every tenfold increase in cost per person comes
with about <strong>9 points less</strong> patient share. It accounts for 44% of the variation
(rank correlation &minus;0.60), so the pattern is real but loose &mdash; more than half of what moves
patient share is something other than price.</p>'''

TAKE = '''<div class="take"><strong>The two purple circles are the counter-examples.</strong>
<strong>Infections</strong> costs $24,713 a person and patients still carry 28.0% &mdash; expensive care
with a routine-care share. <strong>Brain &amp; nervous system</strong> costs $8,939 and patients carry
only 8.5% &mdash; cheap care with a catastrophic-care share. Everything else lines up: maternity and
allergy at over $160,000 a person sit near the floor, while blood disorders and diabetes at under
$1,900 sit at the top.</div>'''

TAIL = '''<p class="note"><strong>Limitations</strong></p>
<ul class="lims">
<li>A guide line, not a model &mdash; 15 points, and price explains under half the spread.</li>
<li>Association only; nothing here shows that price <em>causes</em> the share.</li>
<li>Log x-axis &mdash; equal spacing means ten times the cost, not ten more.</li>
<li><em>Other</em> is a 38-condition catch-all, so its position averages unlike things.</li>
<li>Shares are blends across insurance type; commercial patients pay far more than government ones.</li>
</ul>

<p class="note">Source: <code>sql/analysis/q2_patient_cost_by_care_type.sql</code> &middot;
<code>sql/results/q2_patient_cost_by_care_type_2020_2024.csv</code></p>'''

if __name__ == '__main__':
    open(OUT, 'w').write(build())
    print('wrote', OUT)
