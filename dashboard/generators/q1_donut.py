#!/usr/bin/env python3
"""Generate dashboard/q1_donut.html from sql/results/q1_spend_decomposition_2020_2024.csv.

    python3 dashboard/generators/q1_donut.py

Written 2026-08-29 to replace a generator lost with a session scratch directory.

The subtitle names its total on purpose. This chart is a share of the $72.69B
that carries a diagnosis, NOT of the $99.11B of all spend -- a claim with no
condition on it cannot be attributed to one. Saying "share of all spending"
here would overstate every slice by about a third, which is the error the
concentration chart used to make. Keep the total in the subtitle.

One $3 difference from the chart this replaced: the pooled "all other" tooltip
now reads $26,581,961,971 rather than $26,581,961,974. The CSV's 185 rows sum to
$72,685,492,669 against the $72,685,492,672 reference, three dollars of per-row
rounding. Every other figure and coordinate is identical. The script follows the
CSV, which is the right behaviour -- do not hardcode the old number back.
"""
import csv, math, os

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
SRC  = os.path.join(ROOT, 'sql/results/q1_spend_decomposition_2020_2024.csv')
OUT  = os.path.join(ROOT, 'dashboard/q1_donut.html')

CX, CY, R_OUT, R_IN = 300.0, 285.0, 190.0, 112.0
GAP = 0.344           # degrees trimmed from each end of a slice, for the seam
R_ELBOW, R_BEND = 206.0, 230.0   # leader line: leaves the arc, then bends
RUN = 12.0            # horizontal run after the bend
TOP_N = 3             # named slices; the rest are pooled into grey
FILLS = ['var(--s1)', 'var(--s2)', 'var(--s3)']


def clean(name):
    """'Gingivitis (disorder)' -> 'Gingivitis'."""
    return name.split(' (')[0].strip()


def pt(angle_deg, radius):
    a = math.radians(angle_deg)
    return CX + radius * math.cos(a), CY + radius * math.sin(a)


def load():
    with open(SRC) as fh:
        rows = [(clean(r['Condition']), float(r['Total billed']))
                for r in csv.DictReader(fh)]
    rows.sort(key=lambda x: -x[1])
    total = sum(v for _, v in rows)
    top = rows[:TOP_N]
    rest = sum(v for _, v in rows[TOP_N:])
    slices = [(n, v, FILLS[i]) for i, (n, v) in enumerate(top)]
    slices.append(('All other {} conditions'.format(len(rows) - TOP_N), rest, 'var(--rest)'))
    return slices, total


def arc(a0, a1):
    """One donut slice, trimmed by GAP at each end."""
    a0, a1 = a0 + GAP, a1 - GAP
    ox0, oy0 = pt(a0, R_OUT)
    ox1, oy1 = pt(a1, R_OUT)
    ix1, iy1 = pt(a1, R_IN)
    ix0, iy0 = pt(a0, R_IN)
    large = 1 if (a1 - a0) > 180 else 0
    return ('M{:.2f},{:.2f} A{:.2f},{:.2f} 0 {} 1 {:.2f},{:.2f} '
            'L{:.2f},{:.2f} A{:.2f},{:.2f} 0 {} 0 {:.2f},{:.2f} Z').format(
        ox0, oy0, R_OUT, R_OUT, large, ox1, oy1,
        ix1, iy1, R_IN, R_IN, large, ix0, iy0)


def build():
    slices, total = load()
    o = []
    o.append('<title>Three Conditions</title>')
    o.append(STYLE)
    o.append('<div class="wrap">')
    o.append('<h1>Three conditions, two-thirds of the money</h1>')
    o.append('<p class="sub">Share of $72.7&nbsp;billion in condition-attributable '
             'spend, 2020&ndash;2024.</p>')
    open_svg = ('<div class="figure"><svg viewBox="0 0 760 560" role="img" '
                'aria-label="Donut chart: three conditions account for 63 percent '
                'of condition-attributable spend">')

    svg, ang = [], -90.0
    mids = []
    for name, val, fill in slices:
        sweep = 360.0 * val / total
        svg.append('<path d="{}" fill="{}"><title>{}: ${:,.0f} ({:.1f}%)</title></path>'
                   .format(arc(ang, ang + sweep), fill, name, val, 100 * val / total))
        mids.append(ang + sweep / 2)
        ang += sweep

    # leaders and labels for the named slices only; grey is explained in the note
    for i, (name, val, _) in enumerate(slices[:TOP_N]):
        mid = mids[i]
        ex, ey = pt(mid, R_ELBOW)
        bx, by = pt(mid, R_BEND)
        right = math.cos(math.radians(mid)) > 0
        tx = bx + (RUN if right else -RUN)
        anchor = 'start' if right else 'end'
        lx = tx + (5 if right else -5)
        svg.append('<polyline points="{:.1f},{:.1f} {:.1f},{:.1f} {:.1f},{:.1f}" '
                   'class="lead"/>'.format(ex, ey, bx, by, tx, by))
        svg.append('<text x="{:.1f}" y="{:.1f}" class="lbl" text-anchor="{}">{}</text>'
                   .format(lx, by - 3, anchor, name))
        svg.append('<text x="{:.1f}" y="{:.1f}" class="lsub" text-anchor="{}">'
                   '${:.1f}B &#183; {:.1f}%</text>'
                   .format(lx, by + 15, anchor, val / 1e9, 100 * val / total))

    headline = sum(v for _, v, _ in slices[:TOP_N]) / total
    svg.append('<text x="300" y="279" class="ctr">{:.0f}%</text>'.format(100 * headline))
    svg.append('<text x="300" y="303" class="ctrsub">from just three</text>')
    svg.append('<text x="300" y="319" class="ctrsub">conditions</text>')

    o.append(open_svg + ''.join(svg) + '</svg></div>')
    n_pooled = slices[-1][0].split()[2]
    o.append('<p class="note">Grey covers the remaining {} conditions combined.</p>'
             .format(n_pooled))
    o.append('</div>')
    return '\n'.join(o) + '\n'


STYLE = '''<style>
:root{--surface-1:#fcfcfb;--surface-2:#f4f3f0;--text-primary:#0b0b0b;--text-secondary:#52514e;
--text-muted:#78766f;--s1:#2a78d6;--s2:#eb6834;--s3:#1baf7a;--rest:#d2d0ca;}
@media (prefers-color-scheme:dark){:root:not([data-theme="light"]){--surface-1:#1a1a19;--surface-2:#232322;
--text-primary:#fff;--text-secondary:#c3c2b7;--text-muted:#9a988f;
--s1:#3987e5;--s2:#d95926;--s3:#199e70;--rest:#4a4945;}}
:root[data-theme="dark"]{--surface-1:#1a1a19;--surface-2:#232322;--text-primary:#fff;--text-secondary:#c3c2b7;
--text-muted:#9a988f;--s1:#3987e5;--s2:#d95926;--s3:#199e70;--rest:#4a4945;}
body{background:var(--surface-1);color:var(--text-primary);margin:0;padding:30px 20px;
font:15px/1.55 ui-sans-serif,-apple-system,"Segoe UI",system-ui,sans-serif;}
.wrap{max-width:800px;margin:0 auto;}
h1{font-size:20px;margin:0 0 5px;letter-spacing:-.01em;}
.sub{color:var(--text-secondary);font-size:13.5px;margin:0 0 10px;}
.figure{overflow-x:auto;}
svg{display:block;width:100%;height:auto;min-width:680px;}
path{stroke:var(--surface-1);stroke-width:2;}
.lead{fill:none;stroke:var(--text-muted);stroke-width:1.2;}
.lbl{fill:var(--text-primary);font-size:13.5px;font-weight:600;}
.lsub{fill:var(--text-muted);font-size:12px;}
.ctr{fill:var(--text-primary);font-size:44px;font-weight:700;text-anchor:middle;letter-spacing:-.02em;}
.ctrsub{fill:var(--text-secondary);font-size:13px;text-anchor:middle;}
.note{color:var(--text-muted);font-size:12.5px;margin:6px 0 0;}
</style>'''

if __name__ == '__main__':
    open(OUT, 'w').write(build())
    print('wrote', OUT)
