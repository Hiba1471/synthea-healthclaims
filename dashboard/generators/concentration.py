#!/usr/bin/env python3
"""Generate dashboard/concentration.html from sql/results/q3_lorenz_points_2020_2024.csv.

Written 2026-08-29 to replace a generator that was lost with a session scratch
directory. Verified to reproduce the committed HTML byte for byte, so the chart
stops being hand-maintained: edit this file, re-run, commit both.

    python3 dashboard/generators/concentration.py

The three curves DO NOT share a denominator, which the chart states plainly and
this script must keep stating. Patients and organisations are shares of all
$99.11B of non-admin spend; conditions are a share of only the $72.69B carrying
a diagnosis, since a claim with no condition on it cannot be ranked under one.
An earlier version of the chart claimed all three were out of $99.1B, which
made the conditions curve look more concentrated than a fair comparison shows.
"""
import csv, os

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
SRC  = os.path.join(ROOT, 'sql/results/q3_lorenz_points_2020_2024.csv')
OUT  = os.path.join(ROOT, 'dashboard/concentration.html')

# plot box: x 0-100% -> 70..574, y 0-100% of spend -> 394..28 (inverted)
X0, X1, Y0, Y1 = 70.0, 574.0, 394.0, 28.0
sx = lambda p: X0 + (X1 - X0) * p / 100.0
sy = lambda p: Y0 - (Y0 - Y1) * p / 100.0

# display order is deliberate: hospitals and patients first because they are
# what Q3 uniquely establishes. Conditions last and greyed -- it restates Q1,
# where pregnancy at 39.8% of diagnosed spend was already reported.
SERIES = [
    # csv grain,      label,        css,  legend y, count,       pot,      extra
    ('Organisations', 'Hospitals',  's3', 33.0,  '3,918',     '$99.1B', None),
    ('Patients',      'Patients',   's1', 75.0,  '1.26M',     '$99.1B', None),
    ('Conditions',    'Conditions', 's2', 117.0, '185',       '$72.7B', 'repeats Q1'),
]
# where each curve crosses half the money, as a percentile of the group
HALF = {'Conditions': 2, 'Organisations': 3, 'Patients': 11}

TABLE = [
    ('Hospitals',  's3', '3,918',     '$99.1B', '86.2%', '<strong>86 sites</strong> (2.2%)',          False),
    ('Patients',   's1', '1,259,375', '$99.1B', '48.2%', '<strong>134,198 people</strong> (10.7%)',   False),
    ('Conditions', 's2', '185',       '$72.7B', '89.4%', '2 conditions (1.1%)',                       True),
]


def load():
    curves = {}
    with open(SRC) as fh:
        for r in csv.DictReader(fh):
            curves.setdefault(r['Grain'], []).append(
                (int(r['Pct Entities']), float(r['Pct Spend'])))
    for pts in curves.values():
        pts.sort()
    return curves


def path(pts):
    # every curve starts at the origin: nothing ranked, nothing covered
    d = ['M{:.1f},{:.1f}'.format(X0, Y0)]
    d += ['L{:.1f},{:.1f}'.format(sx(e), sy(s)) for e, s in pts]
    return ' '.join(d)


def build():
    curves = load()
    o = []
    o.append('<title>Spend Concentration</title>')
    o.append(STYLE)
    o.append('<div class="wrap">')
    o.append('<h1>Spending piles up in places, not in people</h1>')
    o.append(SUB)
    o.append(WARN)
    o.append('<div class="figure"><svg viewBox="0 0 700 450" role="img" '
             'aria-label="Lorenz curves of spend concentration for conditions, '
             'hospitals and patients">')
    o.append('  <text class="axis-title" transform="translate(18 211.0) rotate(-90)">'
             'share of total spend</text>')
    o.append('  <text x="322.0" y="436" class="axis-title">share of the group, '
             'ranked most expensive first</text>')
    for pct in (0, 25, 50, 75, 100):
        y, x = sy(pct), sx(pct)
        o.append('  <line x1="{:.1f}" y1="{:.1f}" x2="{:.1f}" y2="{:.1f}" class="grid"/>'
                 .format(X0, y, X1, y))
        o.append('  <text x="59.0" y="{:.1f}" class="tick tick-y">{}%</text>'.format(y + 4, pct))
        o.append('  <text x="{:.1f}" y="416.0" class="tick tick-x">{}%</text>'.format(x, pct))
    o.append('  <line x1="{:.1f}" y1="{:.1f}" x2="{:.1f}" y2="{:.1f}" class="equality"/>'
             .format(X0, Y0, X1, Y1))
    o.append('  <text x="372.4" y="165.4" class="eqlabel" '
             'transform="rotate(-31 372.4 165.4)">perfectly even</text>')
    # curves drawn conditions-first so the flatter patient line lands on top
    for grain in ('Conditions', 'Organisations', 'Patients'):
        css = next(s[2] for s in SERIES if s[0] == grain)
        o.append('  <path d="{}" class="line {}"/>'.format(path(curves[grain]), css))
    for grain, label, css, ly, count, pot, extra in SERIES:
        o.append('  <rect x="586.0" y="{:.1f}" width="10" height="10" rx="2" class="key-{}"/>'
                 .format(ly, css))
        o.append('  <text x="601.0" y="{:.1f}" class="dlabel">{}</text>'.format(ly + 9, label))
        o.append('  <text x="601.0" y="{:.1f}" class="dsub">{} &#183; of {}</text>'
                 .format(ly + 23, count, pot))
        if extra:
            o.append('  <text x="601.0" y="{:.1f}" class="dsub">{}</text>'.format(ly + 36, extra))
        o.append('  <circle cx="{:.1f}" cy="211.0" r="5" class="anno {}"/>'
                 .format(sx(HALF[grain]), css))
    o.append('</svg></div>')
    o.append('<table>')
    o.append('<caption>How few it takes to reach half the money &mdash; '
             'read the pot each row is out of</caption>')
    o.append('<thead><tr><th>Ranked by</th><th>How many exist</th><th>Out of</th>'
             '<th>Priciest 10% cover</th><th>To reach half</th></tr></thead>')
    o.append('<tbody>')
    for label, css, count, pot, top10, half, muted in TABLE:
        o.append('<tr{}><td><span class="key" style="background:var(--{})"></span>{}</td>'
                 '<td>{}</td><td>{}</td><td>{}</td><td>{}</td></tr>'
                 .format(' class="muted"' if muted else '', css, label, count, pot, top10, half))
    o.append('</tbody></table>')
    o.append(NOTES)
    o.append('</div>')
    return '\n'.join(o) + '\n'


STYLE = '''<style>
:root{--surface-1:#fcfcfb;--text-primary:#0b0b0b;--text-secondary:#52514e;--text-muted:#78766f;
--grid:#e6e5e1;--s1:#2a78d6;--s2:#eb6834;--s3:#1baf7a;}
@media (prefers-color-scheme:dark){:root:not([data-theme="light"]){--surface-1:#1a1a19;--text-primary:#fff;
--text-secondary:#c3c2b7;--text-muted:#9a988f;--grid:#33322f;--s1:#3987e5;--s2:#d95926;--s3:#199e70;}}
:root[data-theme="dark"]{--surface-1:#1a1a19;--text-primary:#fff;--text-secondary:#c3c2b7;
--text-muted:#9a988f;--grid:#33322f;--s1:#3987e5;--s2:#d95926;--s3:#199e70;}
body{background:var(--surface-1);color:var(--text-primary);margin:0;padding:28px 20px;
font:15px/1.55 ui-sans-serif,-apple-system,"Segoe UI",system-ui,sans-serif;}
.wrap{max-width:720px;margin:0 auto;}
h1{font-size:19px;margin:0 0 4px;letter-spacing:-.01em;}
.sub{color:var(--text-secondary);font-size:13.5px;margin:0 0 18px;}
.figure{overflow-x:auto;}
svg{display:block;width:100%;height:auto;min-width:640px;}
.grid{stroke:var(--grid);stroke-width:1;}
.equality{stroke:var(--text-muted);stroke-width:1.5;stroke-dasharray:5 4;opacity:.55;}
.eqlabel{fill:var(--text-muted);font-size:11px;}
.line{fill:none;stroke-width:2;stroke-linejoin:round;stroke-linecap:round;}
.s1{stroke:var(--s1);} .s2{stroke:var(--s2);} .s3{stroke:var(--s3);}
circle.s1{fill:var(--s1);stroke:none;} circle.s2{fill:var(--s2);stroke:none;} circle.s3{fill:var(--s3);stroke:none;}
.anno{stroke:var(--surface-1);stroke-width:2;}
.tick{fill:var(--text-muted);font-size:11.5px;}
.tick-y{text-anchor:end;} .tick-x{text-anchor:middle;}
.axis-title{fill:var(--text-secondary);font-size:12px;text-anchor:middle;}
.dlabel{fill:var(--text-primary);font-size:13px;font-weight:600;}
.key-s1{fill:var(--s1);}.key-s2{fill:var(--s2);}.key-s3{fill:var(--s3);}
.dsub{fill:var(--text-muted);font-size:11px;}
table{border-collapse:collapse;width:100%;margin-top:22px;font-size:13.5px;}
th,td{text-align:right;padding:7px 10px;border-bottom:1px solid var(--grid);}
th:first-child,td:first-child{text-align:left;}
th{color:var(--text-secondary);font-weight:600;font-size:12px;}
caption{text-align:left;color:var(--text-secondary);font-size:12.5px;padding-bottom:8px;}
.key{display:inline-block;width:9px;height:9px;border-radius:2px;margin-right:7px;vertical-align:baseline;}
.note{color:var(--text-muted);font-size:12.5px;margin-top:16px;}
.warn{color:var(--text-secondary);font-size:12.5px;line-height:1.5;margin:0 0 18px;
padding:9px 12px;border-left:3px solid var(--s2);background:color-mix(in srgb,var(--s2) 7%,transparent);
border-radius:0 4px 4px 0;}
tr.muted td{color:var(--text-muted);}
</style>'''

SUB = '''<p class="sub">Each line answers: if you rank the group from most expensive to least, how much of the
money have you covered? The further a line bows above the dashed diagonal, the more concentrated the
spending. Dots mark where each line crosses half the money.</p>'''

WARN = '''<p class="warn"><strong>The three lines do not share a total.</strong> Hospitals and patients cover all
<strong>$99.1&nbsp;billion</strong>. Conditions cover only the <strong>$72.7&nbsp;billion</strong> that
has a diagnosis attached &mdash; a claim with no condition on it cannot be ranked under one. The orange
line is drawn out of a smaller pot, so it is not directly comparable with the other two.</p>'''

NOTES = '''<p class="note"><strong>Why conditions are greyed out.</strong> Ranking by condition returns the answer
Q1 already gave &mdash; pregnancy alone is 39.8% of diagnosed spend. It is kept on the chart so the
comparison is visible, not because it is a separate finding. Care types are left off entirely for the same
reason: the top care type is 99.7% one condition, so that line would trace this one.</p>
<p class="note">2020&ndash;2024. Patients are the least concentrated of the three &mdash; the top 1% account for
11.8% of spend, well below the 20&ndash;25% typical of real US claims data. That flatness reflects how this
synthetic dataset generates patients independently, under-producing catastrophic multi-morbidity cases.</p>
<p class="note">Generated by <code>dashboard/generators/concentration.py</code> from
<code>sql/results/q3_concentration_2020_2024.csv</code> and
<code>q3_lorenz_points_2020_2024.csv</code>. Edit the script, not this file.</p>'''

if __name__ == '__main__':
    open(OUT, 'w').write(build())
    print('wrote', OUT)
