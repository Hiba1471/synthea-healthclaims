#!/usr/bin/env python3
"""Generate dashboard/two_ways_expensive.html from
sql/results/q3_hospital_cost_intensity_2020_2024.csv.

    python3 dashboard/generators/q3_two_ways_expensive.py

Carries the actionable half of Q3, which until now existed only as a sentence:
cost per patient runs $4,401 to $144,422 across 731 sites, and that single
number hides two unrelated causes needing two different responses.

Every dot is the same size. Sizing by patient count was tried and dropped: it
introduced a third variable the reader was never asked to compare, and the
largest circles physically covered the cluster they belonged to.

The axes are deliberately the two everyday quantities a stakeholder already
understands -- what it costs each time, and how often people come. Cost per
patient, the number the finding is usually quoted as, is those two multiplied
together, which is exactly what makes it ambiguous. Splitting it back apart is
the whole point of the chart.

BOTH HIGHLIGHTED GROUPS ARE IDENTIFIED BY NAME, NOT BY DATA. Nothing in the
warehouse marks a facility as a VA site or as a hospice. The VA pattern below
matches 12 sites: six say Vet Center or VA Medical Center outright, and three
more -- Auburn Gresham, Lakeside, Parma Community Based Outpatient Clinic -- are
VA community clinics recognisable only if you know the naming convention. That
was confirmed by the user, not derived. All 12 land above 24 visits per patient,
which is corroboration but not proof. Say so on the chart, as the footnote does.

The hospice cluster is the finding most likely to be misread, and the first
version of this chart misread it in the other direction -- calling it purely a
"measurement artefact", which undersold what is actually going on.

Both things are true at once, and the note has to carry both. A hospice
encounter runs 17-54 days against 0 for a clinic appointment, so one record
covers weeks of continuous end-of-life care: the total is large because someone
is very ill for a long time, which is real. But the RATE is modest. Per day,
hospice bills $523-$579 -- below skilled nursing at $777-$917 and roughly a
tenth of an inpatient bed at $6,023 (figures from
delayed_claims_tail_2020_2024.csv, AVG_BILLED divided by AVG_ENCOUNTER_DAYS).

So the practical conclusion survives: there is no inflated price to negotiate
down, because hospice is already among the cheapest care per day in the data.
What fails is the x-axis label. "What one visit costs" quietly assumes visits
are comparable units, and for these 22 sites a visit is a seven-week stay. Do
not restate this as sites being overpriced, and do not restate it as nothing
real happening either.
"""
import csv, math, os, re  # math is used by the log scale

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
SRC  = os.path.join(ROOT, 'sql/results/q3_hospital_cost_intensity_2020_2024.csv')
OUT  = os.path.join(ROOT, 'dashboard/two_ways_expensive.html')

VIEW_W, VIEW_H = 700, 470
PX0, PX1 = 78.0, 636.0          # plot box, horizontal
PY0, PY1 = 384.0, 44.0          # plot box, vertical (inverted)
V_MAX = 58.0                    # top of the visits axis
X_LO, X_HI = 900.0, 18000.0     # price axis, padded past the real 1,013-16,030
# every dot the same size: the message is where sites sit, not how big they
# are. Sizing by patient count added a third variable nobody was asked to read,
# and the largest circles swallowed the cluster they sat in. Patient count is
# still in each tooltip.
DOT_R = 4.0

DEC = (PX1 - PX0) / (math.log10(X_HI) - math.log10(X_LO))
sx = lambda v: PX0 + DEC * (math.log10(v) - math.log10(X_LO))
sy = lambda n: PY0 - (PY0 - PY1) * n / V_MAX

XTICKS = [(1000, '$1K'), (2000, '$2K'), (5000, '$5K'), (10000, '$10K')]
YTICKS = [0, 10, 20, 30, 40, 50]

# Both patterns match on the facility NAME. See the module docstring -- nothing
# in the data labels a site as either of these.
VA   = re.compile(r'vet center|\bva medical|auburn gresham|lakeside clinic|'
                  r'community based outpatient', re.I)
STAY = re.compile(r'hospice|convalescent|palliative|nursing home|home care', re.I)


def group(name):
    if VA.search(name):
        return 'va'
    if STAY.search(name):
        return 'stay'
    return 'other'


def load():
    with open(SRC) as fh:
        rows = [{
            'name':   r['Hospital'],
            'price':  float(r['Billed per Encounter']),
            'visits': float(r['Encounters per Patient']),
            'people': int(r['Patients']),
            'perpat': float(r['Billed per Patient']),
        } for r in csv.DictReader(fh)]
    for r in rows:
        r['grp'] = group(r['name'])
    # ordinary sites first so the two highlighted groups draw on top
    rows.sort(key=lambda r: ({'other': 0, 'stay': 1, 'va': 2}[r['grp']], -r['people']))
    return rows


def build():
    rows = load()
    n = {g: len([r for r in rows if r['grp'] == g]) for g in ('other', 'va', 'stay')}
    o = ['<title>Two Ways to Be Expensive</title>', STYLE, '<div class="wrap">',
         '<h1>The dearest hospitals charge ordinary prices &mdash; their patients '
         'come back fifty times</h1>',
         '<p class="sub">And the ones that really do charge more are mostly hospices, '
         'where a whole stay is billed as one visit. Two different problems, one big '
         'number.</p>',
         '<div class="figure"><svg viewBox="0 0 {} {}" role="img" '
         'aria-label="Each of 731 hospitals plotted by price per visit against visits '
         'per patient">'.format(VIEW_W, VIEW_H)]

    for v in YTICKS:
        y = sy(v)
        o.append('<line class="grid" x1="{:.0f}" y1="{:.1f}" x2="{:.0f}" y2="{:.1f}"/>'
                 .format(PX0, y, PX1, y))
        o.append('<text x="{:.0f}" y="{:.1f}" class="tick tick-y">{}</text>'
                 .format(PX0 - 10, y + 4, v))
    for v, lab in XTICKS:
        x = sx(v)
        o.append('<line class="ticker" x1="{:.1f}" y1="{:.0f}" x2="{:.1f}" y2="{:.0f}"/>'
                 .format(x, PY0, x, PY0 + 5))
        o.append('<text x="{:.1f}" y="{:.0f}" class="tick tick-x">{}</text>'
                 .format(x, PY0 + 20, lab))

    for r in rows:
        o.append('<circle class="pt {}" cx="{:.1f}" cy="{:.1f}" r="{:.1f}"><title>{}\n'
                 '${:,.0f} a visit &#183; {:.1f} visits per patient\n'
                 '${:,.0f} per patient &#183; {:,} patients</title></circle>'
                 .format(r['grp'], sx(r['price']), sy(r['visits']), DOT_R,
                         r['name'], r['price'], r['visits'], r['perpat'], r['people']))

    o.append('<line class="axis" x1="{:.0f}" y1="{:.0f}" x2="{:.0f}" y2="{:.0f}"/>'
             .format(PX0, PY0, PX1, PY0))
    o.append('<text x="{:.0f}" y="{:.0f}" class="axis-title">What one visit costs '
             '&#8212; log scale</text>'.format((PX0 + PX1) / 2, PY0 + 44))
    o.append('<text class="axis-title" transform="translate(20,{:.0f}) rotate(-90)">'
             'Visits per patient over five years</text>'.format((PY0 + PY1) / 2))

    # legend sits top-right, the one empty corner: nothing is both dear and frequent
    lx, ly = 352.0, 66.0
    for i, (g, txt) in enumerate([
            ('va',    '{} veterans’ sites &#8212; they come back constantly'.format(n['va'])),
            ('stay',  '{} hospices &#8212; one whole stay = one visit'.format(n['stay'])),
            ('other', '{} everything else'.format(n['other']))]):
        y = ly + i * 19
        o.append('<circle class="pt {}" cx="{:.0f}" cy="{:.0f}" r="5"/>'.format(g, lx, y - 4))
        o.append('<text x="{:.0f}" y="{:.0f}" class="leg">{}</text>'.format(lx + 12, y, txt))

    o.append('</svg></div>')
    o.append(NOTE)
    o.append('</div>')
    return '\n'.join(o) + '\n'


STYLE = '''<style>
:root{--surface-1:#fcfcfb;--text-primary:#0b0b0b;--text-secondary:#52514e;--text-muted:#78766f;
--grid:#e6e5e1;--s1:#2a78d6;--s2:#eb6834;--s3:#1baf7a;--dim:#a8a69f;}
@media (prefers-color-scheme:dark){:root:not([data-theme="light"]){--surface-1:#1a1a19;--text-primary:#fff;
--text-secondary:#c3c2b7;--text-muted:#9a988f;--grid:#33322f;--s1:#3987e5;--s2:#d95926;--s3:#199e70;
--dim:#6b6a64;}}
:root[data-theme="dark"]{--surface-1:#1a1a19;--text-primary:#fff;--text-secondary:#c3c2b7;
--text-muted:#9a988f;--grid:#33322f;--s1:#3987e5;--s2:#d95926;--s3:#199e70;--dim:#6b6a64;}
body{background:var(--surface-1);color:var(--text-primary);margin:0;padding:28px 20px;
font:15px/1.55 ui-sans-serif,-apple-system,"Segoe UI",system-ui,sans-serif;}
.wrap{max-width:760px;margin:0 auto;}
h1{font-size:20px;margin:0 0 6px;letter-spacing:-.01em;line-height:1.32;}
.sub{color:var(--text-secondary);font-size:13.5px;margin:0 0 16px;}
.figure{overflow-x:auto;}
svg{display:block;width:100%;height:auto;min-width:620px;}
.grid{stroke:var(--grid);stroke-width:1;}
.axis{stroke:var(--text-muted);stroke-width:1;}
.ticker{stroke:var(--text-muted);stroke-width:1;}
.tick{fill:var(--text-muted);font-size:11.5px;}
.tick-y{text-anchor:end;} .tick-x{text-anchor:middle;}
.axis-title{fill:var(--text-secondary);font-size:12px;text-anchor:middle;}
.pt{stroke-width:1;}
.pt.other{fill:var(--dim);fill-opacity:.42;stroke:var(--dim);stroke-opacity:.5;}
.pt.va{fill:var(--s3);fill-opacity:.85;stroke:var(--s3);}
.pt.stay{fill:var(--s2);fill-opacity:.85;stroke:var(--s2);}
.leg{fill:var(--text-secondary);font-size:11.5px;}
.note{color:var(--text-muted);font-size:12.5px;margin-top:16px;line-height:1.55;}
</style>'''

NOTE = '''<p class="note"><strong>The hospices are not overcharging &mdash; but something real is
happening to those patients.</strong> A hospice encounter lasts <strong>17 to 54 days</strong> against
0 days for a clinic appointment, so one record covers weeks of continuous end-of-life care. That is
genuine, serious, expensive care. What it is <em>not</em> is expensive per day: hospice bills
<strong>$523&ndash;$579 a day</strong>, near the bottom of every setting &mdash; below nursing homes at
$777&ndash;$917 and about a tenth of an inpatient bed at $6,023. The length of the stay, not the price of
the care, is what pushes these dots right (<code>delayed_claims_tail_2020_2024.csv</code>). There is no
rate here to negotiate down.</p>
<p class="note"><strong>Both highlighted groups are identified by their names</strong>, because nothing in
the data marks a facility as a VA site or a hospice. Six of the twelve say <em>Vet Center</em> or
<em>VA Medical Center</em> outright; three others are VA community clinics recognisable only from the
naming convention. All twelve sit above 24 visits per patient, which supports the grouping without
proving it.</p>
<p class="note">731 sites with at least 1,000 patients, 2020&ndash;2024. Every dot is the same size &mdash;
position is the message, not scale. Patient counts are in the tooltips. Generated by
<code>dashboard/generators/q3_two_ways_expensive.py</code> from
<code>sql/results/q3_hospital_cost_intensity_2020_2024.csv</code>. Edit the script, not this file.</p>'''

if __name__ == '__main__':
    open(OUT, 'w').write(build())
    print('wrote', OUT)
