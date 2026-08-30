#!/usr/bin/env python3
"""Generate dashboard/places_not_people.html from
sql/results/q3_concentration_2020_2024.csv.

    python3 dashboard/generators/q3_places_not_people.py

A plain-language companion to dashboard/concentration.html, which says the same
thing as a Lorenz curve. The curve is the better chart for an analyst; this one
is for a room that should not have to be taught what a cumulative share is.

THE COMPARISON THIS CHART REFUSES TO DRAW. It is tempting to put 86 against
134,198 and let the near-thousandfold gap carry the slide. That would be
dishonest: there are 321 times more patients than hospitals to begin with, so a
bigger count is arithmetic, not concentration. Measured properly -- as a share
of each group -- hospitals are about five times more concentrated, 2.2% against
10.7%. The bars are therefore drawn as PROPORTIONS, which is the honest picture,
and the raw counts sit in the labels where they make the separate and true point
that 86 sites is a workable list and 134,198 people is not.

Only the Organisations and Patients rows are used. The Conditions and Care types
rows in the same CSV restate Q1 -- see the Q3 section of DATA_ANALYSIS_CONTEXT.md
-- and are left out rather than padding the chart with old news.
"""
import csv, os

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
SRC  = os.path.join(ROOT, 'sql/results/q3_concentration_2020_2024.csv')
OUT  = os.path.join(ROOT, 'dashboard/places_not_people.html')

BAR_X, BAR_W, BAR_H = 108.0, 366.0, 52.0
ROW_Y = [28.0, 126.0]
VIEW_W, VIEW_H = 680, 238

# csv grain -> (label shown, colour token, plural noun for the count line)
ROWS = [('Organisations', 'Hospitals', 's3', 'hospitals'),
        ('Patients',      'Patients',  's1', 'people')]


def load():
    with open(SRC) as fh:
        by = {r['Ranked by']: r for r in csv.DictReader(fh)}
    out = []
    for grain, label, css, noun in ROWS:
        r = by[grain]
        out.append({
            'label': label, 'css': css, 'noun': noun,
            'total': int(r['How many exist']),
            'pct':   float(r['% of them needed to reach half the spend']),
            'few':   int(r['= this many of them']),
        })
    return out


def build():
    rows = load()
    o = ['<title>Places Not People</title>', STYLE, '<div class="wrap">',
         '<h1>86 hospitals carry half the money. No small group of patients does.</h1>',
         '<p class="sub">It takes 134,198 people to reach the same half &mdash; a list '
         'nobody can work through. The hospital list, you could.</p>',
         '<div class="figure"><svg viewBox="0 0 {} {}" role="img" '
         'aria-label="Share of hospitals and share of patients needed to reach half of '
         'all spending">'.format(VIEW_W, VIEW_H)]

    for i, r in enumerate(rows):
        y = ROW_Y[i]
        fill_w = BAR_W * r['pct'] / 100.0
        o.append('<text x="{:.0f}" y="{:.0f}" class="rowlab">{}</text>'
                 .format(BAR_X - 14, y + 33, r['label']))
        o.append('<rect x="{:.0f}" y="{:.0f}" width="{:.0f}" height="{:.0f}" rx="3" '
                 'class="rest"/>'.format(BAR_X, y, BAR_W, BAR_H))
        o.append('<rect x="{:.0f}" y="{:.0f}" width="{:.1f}" height="{:.0f}" rx="3" '
                 'class="fill-{}"/>'.format(BAR_X, y, fill_w, BAR_H, r['css']))
        # the count sits beside the bar, never inside the sliver
        o.append('<text x="{:.0f}" y="{:.0f}" class="count">{:,} {}</text>'
                 .format(BAR_X + BAR_W + 12, y + 24, r['few'], r['noun']))
        o.append('<text x="{:.0f}" y="{:.0f}" class="of">of {:,} &#183; {:.1f}%</text>'
                 .format(BAR_X + BAR_W + 12, y + 42, r['total'], r['pct']))

    o.append('<text x="{:.0f}" y="{:.0f}" class="key">'
             'Coloured = the few that carry half of all spending</text>'
             .format(BAR_X, ROW_Y[1] + BAR_H + 34))
    o.append('</svg></div>')
    o.append(NOTE)
    o.append('</div>')
    return '\n'.join(o) + '\n'


STYLE = '''<style>
:root{--surface-1:#fcfcfb;--text-primary:#0b0b0b;--text-secondary:#52514e;--text-muted:#78766f;
--grid:#e6e5e1;--s1:#2a78d6;--s2:#eb6834;--s3:#1baf7a;--rest:#e3e1dc;}
@media (prefers-color-scheme:dark){:root:not([data-theme="light"]){--surface-1:#1a1a19;--text-primary:#fff;
--text-secondary:#c3c2b7;--text-muted:#9a988f;--grid:#33322f;--s1:#3987e5;--s2:#d95926;--s3:#199e70;
--rest:#3a3936;}}
:root[data-theme="dark"]{--surface-1:#1a1a19;--text-primary:#fff;--text-secondary:#c3c2b7;
--text-muted:#9a988f;--grid:#33322f;--s1:#3987e5;--s2:#d95926;--s3:#199e70;--rest:#3a3936;}
body{background:var(--surface-1);color:var(--text-primary);margin:0;padding:28px 20px;
font:15px/1.55 ui-sans-serif,-apple-system,"Segoe UI",system-ui,sans-serif;}
.wrap{max-width:760px;margin:0 auto;}
h1{font-size:21px;margin:0 0 6px;letter-spacing:-.01em;line-height:1.3;}
.sub{color:var(--text-secondary);font-size:14px;margin:0 0 22px;}
.figure{overflow-x:auto;}
svg{display:block;width:100%;height:auto;min-width:600px;}
.rest{fill:var(--rest);}
.fill-s1{fill:var(--s1);} .fill-s3{fill:var(--s3);}
.rowlab{fill:var(--text-primary);font-size:14.5px;font-weight:600;text-anchor:end;}
.count{fill:var(--text-primary);font-size:14.5px;font-weight:700;}
.of{fill:var(--text-muted);font-size:12.5px;}
.key{fill:var(--text-muted);font-size:12.5px;}
.note{color:var(--text-muted);font-size:12.5px;margin-top:18px;line-height:1.55;}
</style>'''

NOTE = '''<p class="note"><strong>This list is a scope, not a lever.</strong> The 86 sites are worth
knowing because they are few. What to <em>do</em> with them is a separate question, and four candidate
answers have each been tested and ruled out: case management (there is no small patient group &mdash; that
is this chart), price negotiation (a median 7.8% of a site's cost per visit is its prices), chronic-care
management at the busiest sites (those visits are dialysis), and utilisation review (hospitals do
near-identical amounts of work). Acting on the list needs a way to compare like with like &mdash; severity
adjustment, real negotiated rates, or outcomes &mdash; which this dataset does not carry.</p>
<p class="note">2020&ndash;2024, all $99.11&nbsp;billion of non-admin spend. Bars show each
group as a <strong>proportion of itself</strong>, which is the fair comparison: hospitals are about
five times more concentrated than patients, not a thousand times. The raw counts make the separate
point that 86 sites is a list you could work through and 134,198 people is not. The same finding as
<code>concentration.html</code>, which draws it as a curve.</p>
<p class="note">Generated by <code>dashboard/generators/q3_places_not_people.py</code> from
<code>sql/results/q3_concentration_2020_2024.csv</code>. Edit the script, not this file.</p>'''

if __name__ == '__main__':
    open(OUT, 'w').write(build())
    print('wrote', OUT)
