#!/usr/bin/env python3
"""
PRICE-CORRECTED variant of q2_who_bears_the_cost.py, which stays untouched as the
as-billed picture. Reads q2_care_type_breakdown_repriced.sql: eleven
conditions divided down to a real-world benchmark, 174 as billed. Within a
corrected condition the payer-split PERCENTAGE is unchanged (billed and paid
scale together); what moves is the blend across care types, and the dollars.
Generate dashboard/q2_who_bears_the_cost_repriced.html from
sql/results/q2_care_type_breakdown_repriced_2020_2024.csv.

    python3 dashboard/generators/q2_who_bears_the_cost.py

Written 2026-08-29 to replace a generator lost with a session scratch directory.

THE LEDE NAMES ITS DENOMINATOR AND MUST KEEP DOING SO. This chart covers the
$72.69B whose claims carry a real clinical diagnosis -- 73% of spend, not the
whole $99.11B. Describing it as "all spending" would overstate every bar by
about a third. It is the same trap concentration.html fell into and had to be
corrected for; this chart got it right from the start and the wording is load
bearing, not decoration.

Bars are SHARES, not amounts, which is why total bill and people affected are
printed alongside every row. Blood disorders leads the chart at 38.9% and is
13th of 15 on money. Without those two columns the chart would read as a
ranking of importance, which it is not.

The shares are also blends across insurance type -- nobody actually pays
diabetes care's 36.6%; commercial patients pay 74.4% and government ones 8.1%.
That is in the limitations list and should stay there. See
q2_pattern_within_payer.sql.
"""
import csv, os

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
SRC  = os.path.join(ROOT, 'sql/results/q2_care_type_breakdown_repriced_2020_2024.csv')
OUT  = os.path.join(ROOT, 'dashboard/q2_who_bears_the_cost_repriced.html')

X0, X100 = 196.0, 606.0        # 0% and 100% of the bar track
ROW0, ROW_H, BAR_H = 78.0, 28.5, 23
CAT_X, BILL_X, PEOPLE_X = 185, 628, 710

sx = lambda pct: X0 + (X100 - X0) * pct / 100.0


def money(v):
    return '${:,.2f}B'.format(v / 1e9) if v >= 1e9 else '${:,.0f}M'.format(v / 1e6)


def load():
    with open(SRC) as fh:
        rows = [{
            'name':   r['Type of care'],
            'share':  float(r['% of the bill patients pay']),
            'bill':   float(r['Total bill']),
            'paid':   float(r['Paid by patients over 5 years']),
            'ins':    float(r['Paid by insurers']),
            'people': int(r['People affected'].replace(',', '')),
        } for r in csv.DictReader(fh)]
    rows.sort(key=lambda r: -r['share'])
    return rows


def build():
    rows = load()
    o = ['<title>Cost of a Diagnosed Condition</title>', STYLE, '<div class="wrap">',
         '<h1>Who bears the cost of a diagnosed condition</h1>', LEDE, '', H2, SUB,
         '<div class="figure"><svg viewBox="0 0 830 549" xmlns="http://www.w3.org/2000/svg" '
         'role="img" aria-label="Share of the bill paid by patients versus insurers, by '
         'type of care">',
         '<text x="401" y="32" class="colhd" text-anchor="middle">Share of the bill</text>',
         '<text x="628" y="32" class="colhd" text-anchor="start">Total bill</text>',
         '<text x="710" y="32" class="colhd" text-anchor="start">People</text>']

    for pct in (0, 25, 50, 75, 100):
        x = sx(pct)
        o.append('<line class="grid" x1="{:.1f}" y1="60" x2="{:.1f}" y2="512"/>'.format(x, x))
        o.append('<text x="{:.1f}" y="54" class="tick tick-x">{}%</text>'.format(x, pct))

    for i, r in enumerate(rows):
        y = ROW0 + ROW_H * i
        base = y + 16.1                       # text baseline inside the bar
        w = (X100 - X0) * r['share'] / 100.0  # the patient segment
        o.append('<rect class="seg-pat" x="{:.0f}" y="{:.1f}" width="{:.2f}" height="{}" rx="2">'
                 '<title>{}: patients paid {} of {}</title></rect>'
                 .format(X0, y, w, BAR_H, r['name'], money(r['paid']), money(r['bill'])))
        o.append('<rect class="seg-ins" x="{:.2f}" y="{:.1f}" width="{:.2f}" height="{}" rx="2">'
                 '<title>{}: insurers paid {}</title></rect>'
                 .format(X0 + w, y, X100 - X0 - w, BAR_H, r['name'], money(r['ins'])))
        o.append('<text x="{:.1f}" y="{:.1f}" class="inbar">{:.1f}%</text>'
                 .format(X0 + w - 4, base, r['share']))
        o.append('<text x="{}" y="{:.1f}" class="cat">{}</text>'.format(CAT_X, base, r['name']))
        o.append('<text x="{}" y="{:.1f}" class="mval">{}</text>'
                 .format(BILL_X, base, money(r['bill'])))
        o.append('<text x="{}" y="{:.1f}" class="mval">{:,}</text>'
                 .format(PEOPLE_X, base, r['people']))

    o.append('<text x="401" y="538" class="axis-title">Percentage of the bill, patients '
             '(orange) vs insurers (grey)</text>')
    o.append('</svg></div>')
    o.append(TAKE)
    o.append('')
    o.append(TAIL)
    o.append('</div>')
    return '\n'.join(o) + '\n'


STYLE = '''<style>
:root{--surface-1:#fcfcfb;--surface-2:#f4f3f0;--text-primary:#0b0b0b;--text-secondary:#52514e;
--text-muted:#78766f;--grid:#e6e5e1;--pat:#eb6834;--ins:#c8c9c4;}
@media (prefers-color-scheme:dark){:root:not([data-theme="light"]){--surface-1:#1a1a19;--surface-2:#232322;
--text-primary:#fff;--text-secondary:#c3c2b7;--text-muted:#9a988f;--grid:#33322f;--pat:#e8712f;--ins:#6c6c62;}}
:root[data-theme="dark"]{--surface-1:#1a1a19;--surface-2:#232322;--text-primary:#fff;--text-secondary:#c3c2b7;
--text-muted:#9a988f;--grid:#33322f;--pat:#e8712f;--ins:#6c6c62;}
*{box-sizing:border-box}
body{background:var(--surface-1);color:var(--text-primary);margin:0;padding:32px 20px 48px;
font:15px/1.55 ui-sans-serif,-apple-system,"Segoe UI",system-ui,sans-serif;}
.wrap{max-width:820px;margin:0 auto;}
h1{font-size:23px;margin:0 0 6px;letter-spacing:-.02em;}
.lede{color:var(--text-secondary);font-size:14px;margin:0 0 26px;}
h2{font-size:17px;margin:0 0 4px;letter-spacing:-.01em;}
.sub{color:var(--text-secondary);font-size:13.5px;margin:0 0 16px;}
.figure{overflow-x:auto;background:var(--surface-2);border-radius:10px;padding:16px 12px 10px;}
svg{display:block;width:100%;height:auto;min-width:700px;}
.grid{stroke:var(--grid);stroke-width:1;}
.tick{fill:var(--text-muted);font-size:11px;} .tick-x{text-anchor:middle;}
.cat{fill:var(--text-primary);font-size:12px;text-anchor:end;}
.seg-pat{fill:var(--pat);} .seg-ins{fill:var(--ins);}
.inbar{fill:#fff;font-size:9px;font-weight:700;text-anchor:end;}
.mval{fill:var(--text-muted);font-size:11px;text-anchor:start;}
.colhd{fill:var(--text-secondary);font-size:10px;letter-spacing:.05em;text-transform:uppercase;}
.axis-title{fill:var(--text-secondary);font-size:11.5px;text-anchor:middle;}
.note{color:var(--text-muted);font-size:12.5px;margin:16px 0 0;}
.lims{color:var(--text-muted);font-size:12.5px;margin:5px 0 0;padding-left:18px;}
.lims li{margin:2px 0;}
.take{background:var(--surface-2);border-left:3px solid var(--pat);padding:11px 15px;border-radius:0 7px 7px 0;
margin:18px 0 0;font-size:13.5px;color:var(--text-primary);}
</style>'''

LEDE = '''<p class="lede">Synthea healthcare claims, 2020&ndash;2024. Covers the $72.69 billion whose claims carry a
real clinical diagnosis &mdash; <strong>73% of all spend</strong>, not the whole $99.11B &mdash; split
between what patients paid out of pocket and what their insurers paid, across 15 types of care.
The remaining 27%, where the diagnosis field holds encounter metadata rather than an illness, is
excluded &mdash; see Limitations.</p>'''

H2 = '''<h2>Patients carry 17.6% of this bill &mdash; and the largest shares fall on the cheapest care</h2>'''

SUB = '''<p class="sub">Ordered by the share patients carry. Total bill and number of people are shown
alongside, because share alone says nothing about size.</p>'''

TAKE = '''<div class="take"><strong>Member-paid share is inverted against cost.</strong> The types of care where members carry the most are the cheap, routine ones: blood disorders at 38.9% of a $121M bill, diabetes and metabolic care at 36.6% of $435M. The expensive ones are heavily insured: cancer sits last at 7.4% of $2.78B. Dental is the one place a large share and real money meet, at 25.8% of a $2.45B bill falling on 938,009 people. <strong>All figures price-corrected</strong>; as billed the same four read 38.9% of $121M, 36.6% of $435M, 8.3% of $7.1B and 27.9% of $11.83B.</div>'''

TAIL = '''<p class="note"><strong>Limitations</strong></p>
<ul class="lims">
<li>Bars are shares, not amounts &mdash; blood disorders leads on share, 13th of 15 on money.</li>
<li>Shares are blends across insurance type; nobody pays diabetes care&rsquo;s 36.6%.</li>
<li><strong>People</strong> is not additive &mdash; sums to 3,476,252 against 1,259,375 patients.</li>
<li>Eleven conditions are price-corrected here; 174 are still as billed, so the dollar column remains a mix.</li>
<li>The 20.4% headline is that measure over all $99.11B as billed, and 23.3% price-corrected.</li>
</ul>

<p class="note">Source: <code>sql/analysis/q2_care_type_breakdown_repriced.sql</code> &middot;
<code>sql/results/q2_care_type_breakdown_repriced_2020_2024.csv</code></p>'''

if __name__ == '__main__':
    open(OUT, 'w').write(build())
    print('wrote', OUT)
