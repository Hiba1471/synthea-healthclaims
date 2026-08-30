#!/usr/bin/env python3
"""Generate dashboard/analysis_report.html -- the client-facing report.

    python3 dashboard/generators/analysis_report.py

Assembles one page from the charts already built in dashboard/. It does NOT
recompute anything: every figure is lifted from its own generated HTML, so a
number can only change here by changing it at source and rebuilding that chart
first. Run the chart generators before this one.

WHY THE CSS IS SCOPED, AND WHY REMOVING THAT WILL BREAK THINGS SILENTLY.
Nineteen class names are defined differently across the nine charts, and `.key`
is a flex container in one chart and an SVG text fill in another. Dropping the
stylesheets onto one page unchanged lets whichever loads last win, which does
not error -- it quietly repaints an earlier figure with the wrong rules. Every
chart's rules are therefore prefixed with that chart's own wrapper class.

Colour tokens are the exception and are hoisted, not scoped: 26 of the 27
`:root` custom properties are identical across all charts, so they are declared
once for the page in all three theme states. The single disagreement, `--rest`,
is redefined inside the one wrapper that wants the other grey.

NO RECOMMENDATIONS. This pass carries findings only. Q3's recommendations were
dismantled by testing and Q1's have not been through the same scrutiny, so the
report states what is true and stops there. If that changes, the place to add it
is a section per finding, not a sentence smuggled into "why it matters".

The client is invented. See the plan file; the mission is what makes the three
questions hang together, so do not reword it casually.
"""
import os, re

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
DASH = os.path.join(ROOT, 'dashboard')
OUT  = os.path.join(DASH, 'analysis_report.html')

# page chrome belonging to each chart's own standalone page -- never wanted here
CHROME = {'body', '.wrap', 'h1', 'h2', '.lede', '.sub', '.take', '.note',
          '.lims', '.lims li', '.fine', '.note.fine', 'strong', 'code',
          '.note strong', '.colhd'}


def _blocks(css):
    """Split a stylesheet into (theme_blocks, [(selector, body)])."""
    theme, rules, i, n = [], [], 0, len(css)
    while i < n:
        while i < n and css[i] in ' \n\t\r':
            i += 1
        if i >= n:
            break
        if css[i] == '@':                       # @media { :root { ... } }
            depth, j = 0, i
            while j < n:
                if css[j] == '{':
                    depth += 1
                elif css[j] == '}':
                    depth -= 1
                    if depth == 0:
                        j += 1
                        break
                j += 1
            theme.append(css[i:j].strip())
            i = j
            continue
        m = re.compile(r'([^{}]+)\{([^}]*)\}').match(css, i)
        if not m:
            i += 1
            continue
        sel, body = m.group(1).strip(), m.group(2).strip()
        (theme if sel.startswith(':root') else rules).append(
            css[i:m.end()].strip() if sel.startswith(':root') else (sel, body))
        i = m.end()
    return theme, rules


def scope_css(css, wrap):
    """Prefix every rule with `.wrap`, dropping the chart's own page chrome."""
    theme, rules = _blocks(css)
    out = []
    for sel, body in rules:
        parts = [p.strip() for p in sel.split(',') if p.strip()]
        keep = [p for p in parts if p not in CHROME]
        if not keep:
            continue
        out.append('.%s %s{%s}' % (wrap, (', .%s ' % wrap).join(keep), body))
    return theme, out


def figure_of(name):
    """The <div class="figure"> from a built chart, plus any legend after it."""
    with open(os.path.join(DASH, name + '.html')) as fh:
        s = fh.read()
    css = re.search(r'<style>(.*?)</style>', s, re.S).group(1)
    figs = re.findall(r'<div class="figure">.*?</svg></div>', s, re.S)
    keys = re.findall(r'<div class="key">.*?</div>\s*(?=<|$)', s, re.S)
    return css, figs, keys


# figure key -> (source chart, which figure in it, wrapper class)
FIGURES = {
    'donut':     ('q1_donut',                             0, 'fig-donut'),
    'top20':     ('where_the_money_goes',                 0, 'fig-top20'),
    'whobears':  ('q2_who_bears_the_cost',                0, 'fig-whobears'),
    'cheapcare': ('q2_share_vs_cost_per_person',          0, 'fig-cheapcare'),
    'insurance': ('q2_same_condition_different_insurance', 0, 'fig-insurance'),
    'places':    ('places_not_people',                    0, 'fig-places'),
    'lorenz':    ('concentration',                        0, 'fig-lorenz'),
    'hospitals': ('two_ways_expensive',                   0, 'fig-hospitals'),
}


def collect():
    """Pull every figure and its scoped CSS. Returns (theme_css, css, figs)."""
    theme, css, figs = [], [], {}
    for key, (chart, idx, wrap) in FIGURES.items():
        raw, found, keys = figure_of(chart)
        t, rules = scope_css(raw, wrap)
        for b in t:
            if b not in theme:
                theme.append(b)          # tokens are shared; declare each once
        css.extend(rules)
        legend = keys[idx] if idx < len(keys) else ''
        figs[key] = '<div class="%s">%s%s</div>' % (wrap, found[idx], legend)
    return theme, css, figs


def figure(n, key, caption, figs):
    return ('<figure class="fig">{}\n<figcaption><span class="fignum">Figure {}.</span> '
            '{}</figcaption></figure>').format(figs[key], n, caption)


def build():
    theme, css, figs = collect()
    o = ['<title>Calder Health — Five-Year Claims Analysis</title>',
         '<style>', PAGE_CSS, '\n'.join(theme), '\n'.join(css),
         # the one token the charts disagree on
         '.fig-places .rest{fill:#d2d0ca;}',
         '@media (prefers-color-scheme:dark){:root:not([data-theme="light"]) '
         '.fig-places .rest{fill:#3a3936;}}',
         '</style>',
         '<div class="wrap">', HEADER, ABOUT, DATASECTION, HOWTOREAD, NORTHSTAR, SUMMARY,
         NOTANSWERED,
         '<h2 class="sec">The findings</h2>']

    for i, f in enumerate(FINDINGS, 1):
        o.append('<section class="finding"><h3><span class="fno">Finding %d</span>%s</h3>'
                 % (i, f['title']))
        for n, key, cap in f['figures']:
            o.append(figure(n, key, cap, figs))
        o.append('<div class="prose"><p><strong>What this shows.</strong> %s</p>'
                 '<p><strong>Why it matters for Calder.</strong> %s</p></div>'
                 % (f['shows'], f['why']))
        o.append('<div class="examined"><p class="exhd">What was examined</p><ul>%s</ul></div>'
                 % ''.join('<li>%s</li>' % b for b in f['examined']))
        o.append('</section>')

    o.append(FOOTER)
    o.append('</div>')
    return '\n'.join(o) + '\n'


PAGE_CSS = '''
:root{--surface-1:#fcfcfb;--surface-2:#fff;--text-primary:#0b0b0b;--text-secondary:#52514e;
--text-muted:#78766f;--rule:#e6e5e1;--accent:#2a78d6;--warn:#eb6834;--card:#fff;}
@media (prefers-color-scheme:dark){:root:not([data-theme="light"]){--surface-1:#171716;
--surface-2:#1f1f1e;--text-primary:#fff;--text-secondary:#c3c2b7;--text-muted:#9a988f;
--rule:#33322f;--accent:#3987e5;--warn:#d95926;--card:#232322;}}
:root[data-theme="dark"]{--surface-1:#171716;--surface-2:#1f1f1e;--text-primary:#fff;
--text-secondary:#c3c2b7;--text-muted:#9a988f;--rule:#33322f;--accent:#3987e5;
--warn:#d95926;--card:#232322;}
body{background:var(--surface-1);color:var(--text-primary);margin:0;padding:40px 20px 72px;
font:16px/1.65 ui-sans-serif,-apple-system,"Segoe UI",system-ui,sans-serif;}
.wrap{max-width:860px;margin:0 auto;}
.eyebrow{font-size:11.5px;letter-spacing:.13em;text-transform:uppercase;color:var(--text-muted);
font-weight:650;margin:0 0 10px;}
h1.title{font-size:31px;line-height:1.2;letter-spacing:-.02em;margin:0 0 10px;}
.standfirst{font-size:17px;color:var(--text-secondary);margin:0 0 6px;max-width:64ch;}
.meta{font-size:13px;color:var(--text-muted);margin:14px 0 0;}
h2.sec{font-size:12px;letter-spacing:.11em;text-transform:uppercase;color:var(--text-muted);
font-weight:650;margin:52px 0 16px;padding-bottom:8px;border-bottom:1px solid var(--rule);}
h3{font-size:20px;line-height:1.3;letter-spacing:-.01em;margin:0 0 16px;}
.fno{display:block;font-size:11px;letter-spacing:.1em;text-transform:uppercase;
color:var(--accent);font-weight:700;margin-bottom:5px;}
p{margin:0 0 13px;}
.mission{border-left:3px solid var(--accent);padding:2px 0 2px 18px;margin:0 0 20px;
font-size:17px;line-height:1.55;color:var(--text-primary);}
.cards{display:grid;grid-template-columns:repeat(3,1fr);gap:14px;margin:0 0 8px;}
@media (max-width:700px){.cards{grid-template-columns:1fr;}}
.card{background:var(--card);border:1px solid var(--rule);border-radius:10px;padding:17px 18px;}
.card .lbl{font-size:11px;letter-spacing:.08em;text-transform:uppercase;color:var(--text-muted);
font-weight:650;margin-bottom:8px;}
.card .big{font-size:27px;font-weight:700;letter-spacing:-.02em;line-height:1.1;}
.card .sub2{font-size:12.5px;color:var(--text-secondary);margin-top:7px;line-height:1.45;}
.callout{background:var(--card);border:1px solid var(--rule);border-left:3px solid var(--warn);
border-radius:8px;padding:16px 18px;margin:0 0 8px;}
.callout p{font-size:14px;color:var(--text-secondary);margin:0 0 9px;}
.callout p:last-child{margin:0;}
.callout strong{color:var(--text-primary);}
ul{margin:0 0 13px;padding-left:20px;}
li{margin-bottom:7px;color:var(--text-secondary);}
li strong{color:var(--text-primary);}
.summary li{font-size:15.5px;margin-bottom:11px;}
section.finding{margin:0 0 46px;padding:0 0 6px;}
figure.fig{margin:0 0 8px;}
figcaption{font-size:12.5px;color:var(--text-muted);margin-top:9px;line-height:1.5;}
.fignum{color:var(--text-primary);font-weight:650;}
.prose{margin-top:20px;}
.prose p{font-size:15.5px;color:var(--text-secondary);}
.prose strong{color:var(--text-primary);}
.examined{margin-top:16px;background:var(--card);border:1px solid var(--rule);
border-radius:8px;padding:15px 18px 8px;}
.exhd{font-size:11px;letter-spacing:.09em;text-transform:uppercase;color:var(--text-muted);
font-weight:650;margin:0 0 10px;}
.examined li{font-size:14px;}
footer{margin-top:56px;padding-top:18px;border-top:1px solid var(--rule);
font-size:12.5px;color:var(--text-muted);}
code{font-family:ui-monospace,SFMono-Regular,Menlo,monospace;font-size:.9em;}
'''

HEADER = '''<p class="eyebrow">Calder Health &middot; Prepared for the 2026 planning cycle</p>
<h1 class="title">Where five years of spend went, and who carried it</h1>
<p class="standfirst">An analysis of 68.6 million claims across 1.26 million members,
2020&ndash;2024.</p>
<p class="meta">Findings only. Recommendations follow in a later pass.</p>'''

ABOUT = '''<h2 class="sec">About Calder Health</h2>
<p class="mission"><strong>Mission.</strong> To keep comprehensive cover affordable for every
member, in every place they seek care &mdash; measuring affordability by what a member actually
pays rather than by what a plan spends, and holding that standard equally across commercial and
government lines.</p>
<p>Calder Health is a non-profit health plan headquartered in Cleveland, serving <strong>1.26
million members</strong> with further concentrations in Chicago, Detroit and Northeast Ohio.
Members are treated across a network of <strong>3,918 facilities</strong>, from single-site
clinics to large teaching hospitals. The plan operates two lines of business, and they are
designed differently:</p>
<ul>
<li><strong>Commercial</strong> &mdash; employer group plans, built on a deductible and
coinsurance with an annual out-of-pocket maximum. A member pays a share of each bill until the
annual maximum is reached, after which the plan pays everything.</li>
<li><strong>Government</strong> &mdash; Medicaid and Medicare managed care, built on a flat copay
per visit. A member pays the same small amount whatever the bill comes to.</li>
</ul>
<p>That difference turns out to matter more than almost anything else in this report. The same
condition can cost a commercial member ten times what it costs a government member, and it is the
plan&rsquo;s own benefit design producing the gap.</p>
<p>The mission sets the shape of the analysis. Affordability measured by what members pay &mdash;
rather than by total spend &mdash; is why member cost burden sits among the headline metrics
instead of in an appendix. &ldquo;In every place they seek care&rdquo; is why facilities are
examined separately from conditions. &ldquo;Equally across both lines&rdquo; is why every figure
that can be split by line of business has been.</p>
<p><strong>The brief.</strong> Before benefits are set and networks negotiated for 2026, establish
three things: where the money went, who bore it, and where it concentrates.</p>'''

DATASECTION = '''<h2 class="sec">About the data</h2>
<p>Claims were drawn from a read-only Snowflake share,
<code>SYNTHETIC_HEALTHCARE_DATA_CLINICAL_AND_CLAIMS.SILVER</code>, containing Synthea-generated
synthetic healthcare records &mdash; 887 million claim transactions across 124 million claims and
1.4 million simulated patients in total.</p>
<p><strong>Time frame.</strong> All figures cover <strong>1 January 2020 to 31 December 2024</strong>,
five complete years. The window matters: unfiltered, the source spans simulated history back to
1914, and cumulative totals taken across it are not meaningful. Within the window the analysis
covers <strong>68.6 million claims, 1,259,375 patients and $99.11 billion billed</strong>.</p>
<p><strong>Tables used.</strong></p>
<ul>
<li><code>SILVER.CLAIMS</code> &mdash; diagnosis fields, used to attach spend to a condition.</li>
<li><code>SILVER.ENCOUNTERS</code> &mdash; visit class, dates and the facility each visit belongs
to.</li>
<li><code>SILVER.ORGANIZATIONS</code> &mdash; facility name and city.</li>
<li><code>SILVER.PATIENTS</code> &mdash; dates of birth, used only for the age check behind the
preventive-care question.</li>
</ul>
<p>Two curated objects sit in front of the raw share and every query reads through them, because
the source carries traps that return confident, plausible, wrong answers rather than errors:</p>
<ul>
<li><code>V_CLAIMS_TX_CLEAN</code> &mdash; claim transactions with the money columns corrected,
payer collapsed to type, administrative rows flagged, and the date window applied.</li>
<li><code>CODE_DICTIONARY</code> &mdash; 1,453 rows mapping every clinical code to one canonical
name and category, resolving all nine code fields.</li>
</ul>
<p><strong>Data dictionary.</strong> Full table and column references, together with the known
traps in the source data, are documented in
<a href="../DATA_ANALYSIS_CONTEXT.md">DATA_ANALYSIS_CONTEXT.md</a> &sect;25&ndash;26. Every figure
in this report traces to a saved query in <code>sql/analysis/</code> and a result file in
<code>sql/results/</code>.</p>'''

HOWTOREAD = '''<h2 class="sec">How to read these numbers</h2>
<div class="callout">
<p><strong>This analysis runs on simulated claims data, and some of it is not realistic.</strong>
Read the shape, not the price tag.</p>
<p><strong>Trust:</strong> rankings, shares, ratios, and how concentrated things are. Which
conditions dominate, who pays what proportion, how few sites carry the spend &mdash; these hold up
and are the basis of everything below.</p>
<p><strong>Do not trust:</strong> absolute dollar amounts. A pregnancy bills <strong>8.6&times;
what it costs in reality</strong>. No per-case figure from this report should be quoted
elsewhere.</p>
<p><strong>Cannot be answered here at all:</strong> anything about negotiated rates, denials, bad
debt or collections. In this data every claim is paid in full, and no provider is charged a
different price from any other. Those are properties of the simulation, not findings about
Calder.</p>
</div>'''

NORTHSTAR = '''<h2 class="sec">The three numbers Calder steers by</h2>
<div class="cards">
<div class="card"><div class="lbl">Total cost of care</div><div class="big">$99.1B</div>
<div class="sub2">Billed across five years. $72.7B of it attaches to a specific diagnosis; the
rest is care recorded without one.</div></div>
<div class="card"><div class="lbl">Member cost burden</div><div class="big">20.4%</div>
<div class="sub2">$20.3B paid out of pocket &mdash; $16,084 per member over five years. This is
the number the mission lives or dies on.</div></div>
<div class="card"><div class="lbl">Spend concentration</div><div class="big">86 sites</div>
<div class="sub2">Of 3,918 facilities, 86 carry half of all spending. A list short enough to work
through by hand.</div></div>
</div>'''

SUMMARY = '''<h2 class="sec">Executive summary</h2>
<ul class="summary">
<li><strong>Twenty conditions carry 91% of the bill that can be attributed to a diagnosis</strong>
&mdash; and pregnancy alone is 39.8% of it. Spending is not spread thin; it sits in a handful of
places.</li>
<li><strong>Members carry a fifth of the total, and it lands hardest on the cheapest care.</strong>
They pay 41.6% of a wellness visit and 8.6% of an inpatient stay. The inexpensive, routine things
are what people actually feel.</li>
<li><strong>Which plan a member holds matters more than what is wrong with them.</strong>
Prediabetes costs a commercial member 85.0% of the bill and a government member 8.5% &mdash; the
same care, a ten-fold difference, produced by benefit design rather than by illness.</li>
<li><strong>Spending concentrates in places, not in people.</strong> 86 of 3,918 sites carry half
the money, but it takes 134,198 members to reach the same half. There is no small group of
high-cost members to manage.</li>
<li><strong>The most expensive facilities are not charging more.</strong> Reprice every procedure
identically and the gap between sites barely moves &mdash; only 7.8% of a site&rsquo;s cost per
visit is its prices. Facilities differ in what they treat, not in what they charge.</li>
</ul>'''

NOTANSWERED = '''<h2 class="sec">What this analysis could not answer</h2>
<p>Stated plainly so that silence is not mistaken for a clean bill of health.</p>
<ul>
<li><strong>Whether members skip preventive care.</strong> Wellness visits reach 1,259,199 of the
1,259,375 members, and the small variation that exists tracks who is in each group rather than
what they received. The data schedules these visits by protocol, so it cannot show anyone
declining or missing care. The answerable neighbour of this question is Finding 2.
(<code>q3_preventive_access.sql</code>)</li>
<li><strong>Whether any facility is efficient.</strong> Every difference between sites resolves to
what they treat. Prices barely vary, and neither does the amount of work done for a given
condition.</li>
<li><strong>Anything about denials, collections or bad debt.</strong> Every claim in this data is
paid in full.</li>
<li><strong>Whether this membership is sicker or healthier than the market.</strong> The
population is generated, not observed, and its very sickest members are under-represented compared
with real claims data.</li>
</ul>'''

FOOTER = '''<footer>Calder Health is an illustrative client. The analysis is real and reproducible;
every figure traces to a saved query in <code>sql/analysis/</code> and a result file in
<code>sql/results/</code>. Generated by <code>dashboard/generators/analysis_report.py</code> &mdash;
edit the script, not this page.</footer>'''


FINDINGS = [
 {'title': 'Twenty conditions carry nearly all of the bill, and one of them is pregnancy',
  'figures': [(1, 'donut', 'Diagnosed spend by condition, 2020&ndash;2024. Pregnancy is the '
                           'single largest slice at 39.8%.'),
              (2, 'top20', 'The twenty largest conditions by total billed. The first bar is '
                           'more than three times the second.')],
  'shows': 'Of the $72.7B can be attached to a specific diagnosis, <strong>twenty conditions '
           'account for 90.8%</strong> &mdash; and 66.6% of everything the plan spends. Normal '
           'pregnancy alone is <strong>39.8%</strong>, more than the next three conditions '
           'combined. Ranking by cost per member reorders the list completely: gingivitis '
           'spreads $10,661 across 800,465 members, while lung cancer concentrates $1,416,145 '
           'into 2,384.',
  'why': 'It tells Calder where to look and, just as usefully, where not to. A programme aimed at '
         'the long tail of conditions would be working on a third of spending at most. It also '
         'warns against a single approach: gingivitis is expensive because it reaches almost '
         'everyone, lung cancer because it is intense for very few. Those are different '
         'problems that happen to sit on the same list.',
  'examined': [
    'Total billed per condition, ranked, against total billed per member &mdash; the two '
    'rankings disagree sharply and the disagreement is the point.',
    'Whether pregnancy at 39.8% is credible. The number of visits per pregnancy is plausible '
    '(11.1, against a real-world 10&ndash;15); the price per visit is not.',
    'Whether the top twenty are extreme on one driver or several. They are moderately extreme '
    'on all three at once &mdash; members reached, visits each, cost per visit &mdash; and the '
    'multiplication does the rest.',
    'Whether hospitals differ in what they charge for the same condition. For eight of the ten '
    'largest, barely at all.']},

 {'title': 'Members carry a fifth of the bill, and it falls hardest on the cheapest care',
  'figures': [(3, 'whobears', 'Share of the bill paid by members rather than the plan, by type '
                              'of care.'),
              (4, 'cheapcare', 'Cost per member against the share they carry. The cheaper the '
                               'care, the more of it they pay.')],
  'shows': 'Members bear <strong>20.4% of all spend &mdash; $20.3B</strong>, or $16,084 each '
           'across five years. The burden runs <strong>opposite to cost</strong>: they pay '
           '<strong>41.6% of a wellness visit and 8.6% of an inpatient stay</strong>. Across '
           'types of care the same inversion holds &mdash; blood disorders sit at 38.9% of a '
           '$121M bill, cancer at 8.3% of a $7.1B one.',
  'why': 'This is the mission measured directly, and it reads badly. The care a member pays most '
         'for is the routine, inexpensive, easily-deferred kind &mdash; a check-up, a filling, a '
         'screening. The care the plan absorbs is the catastrophic kind they cannot defer '
         'anyway. Dental is the clearest single case: 27.9% of an $11.83B bill, falling on '
         '938,009 people.',
  'examined': [
    'Member share by type of care, with total bill and number of people alongside &mdash; share '
    'alone says nothing about size.',
    'Whether the pattern survives inside one line of business, or was an artefact of mixing '
    'them. It strengthens: the relationship is clearer within commercial and within government '
    'than across both together.',
    'The two care types that appeared to break the pattern. Neither does &mdash; one is skewed '
    'by a handful of very large claims, the other is 90.2% government-funded.',
    'Why the mechanism differs by line of business, which is Finding 3.']},

 {'title': 'Which plan a member holds matters more than what is wrong with them',
  'figures': [(5, 'insurance', 'The ten conditions where members carry the most, split by line '
                               'of business. The gap is the plan, not the illness.')],
  'shows': 'For every one of the ten conditions where members carry the most, <strong>commercial '
           'members pay a larger share than government members</strong> &mdash; never by less '
           'than 12.9 points. Prediabetes is the extreme: <strong>85.0% for a commercial member '
           'against 8.5% for a government one</strong>, for identical care. Over five years a '
           'government member pays $2,118 out of pocket, a commercial member $19,178, and an '
           'uninsured one $61,742.',
  'why': 'This gap is the plan&rsquo;s. It is not the market, not the providers, not how sick anyone is '
         '&mdash; it is the difference between a flat copay and a deductible with an annual '
         'maximum. Cheap routine care never accumulates enough in a year to reach a commercial '
         'member&rsquo;s out-of-pocket maximum, so they pay coinsurance on all of it; a '
         'government member pays their copay and nothing more. Any figure quoted as '
         '&ldquo;what members pay&rdquo; describes no actual member.',
  'examined': [
    'The ten highest-burden conditions, split three ways, using the typical year rather than '
    'five years pooled so the range is visible.',
    'Whether the gap is stable or a single bad year. It holds in all five.',
    'The mechanism behind it, measured rather than assumed &mdash; a flat $0&ndash;50 per claim '
    'on one side, a deductible and annual cap on the other.',
    'Where a blended figure would mislead. Commercial members span 6.7% to 74.4% by care type, '
    'government members 0.6% to 8.1%; the blend describes neither.']},

 {'title': 'Spending concentrates in places, not in people',
  'figures': [(6, 'places', 'How much of each group is needed to reach half of all spending.'),
              (7, 'lorenz', 'The same finding as a curve: how quickly spend accumulates as you '
                            'work down each ranked list.')],
  'shows': '<strong>86 of the 3,918 facilities carry half of everything the plan spends</strong> &mdash; '
           '2.2% of sites. Reaching the same half through members takes <strong>134,198 people, '
           '10.7%</strong> of the membership. Measured fairly, as a share of each group, sites '
           'are about <strong>five times more concentrated than members</strong>.',
  'why': 'It settles where attention is worth spending. 86 sites is a list a team can '
         'genuinely work through one at a time. 134,198 members is not a list at all &mdash; it '
         'is a small city, and no case-management programme reaches it. This is the one thing '
         'this analysis establishes that looking at conditions or costs alone never could, '
         'because neither counts people.',
  'examined': [
    'Concentration measured four ways &mdash; by member, by site, by condition, by type of care '
    '&mdash; to check the answer was not an artefact of one grouping.',
    'Whether comparing 86 against 134,198 is fair. It is not, on its own: there are 321 times '
    'more members than sites, so the fair comparison is 2.2% against 10.7%.',
    'How the member concentration compares with real claims data. This population is flatter &mdash; the '
    'top 1% carry 11.8% where real books run 20&ndash;25% &mdash; so if anything this '
    'understates how few members matter.',
    'Whether the site concentration is actionable, which is Finding 5.']},

 {'title': 'The most expensive facilities are not charging more',
  'figures': [(8, 'hospitals', 'Every facility by what an average visit costs and how often '
                               'members return. Three groups, doing three different things.')],
  'shows': 'Cost per member runs from <strong>$4,401 to $144,422</strong> across facilities &mdash; '
           'a 33-fold spread. But reprice every procedure in the data to a single common rate and '
           'that spread barely moves, from 15.8&times; to 15.2&times;. <strong>A median of just '
           '7.8% of a site&rsquo;s cost per visit reflects what it charges</strong>; the rest is '
           'what it treats. The same holds for how much gets done: for the typical condition, '
           'facilities perform near-identical amounts of work.',
  'why': 'The obvious reading of a 33-fold spread &mdash; that some hospitals overcharge &mdash; '
         'is wrong, and acting on it would waste a planning cycle. The sites that look most '
         'expensive per member are running dialysis three times a week at ordinary prices. The '
         'ones that look most expensive per visit are hospices, where a multi-week stay is billed '
         'as a single visit. Even pregnancy, the one condition where facilities genuinely differ, '
         'splits into delivery units and antenatal clinics doing different halves of the same '
         'care. There is no pricing problem here to find.',
  'examined': [
    'Whether the spread is price or case mix, by repricing every procedure to its all-facility '
    'average and remeasuring. It is case mix.',
    'Whether facilities differ in how much they do for the same condition. For the typical '
    'condition, no &mdash; and the one big exception is pregnancy.',
    'What separates cheap from expensive pregnancy sites. At the cheapest, 95.5% of women give '
    'birth on site; at the most expensive, 6.8%. Delivery units against antenatal clinics.',
    'The two groups that stand out on the chart, both identified by facility name rather than '
    'by anything in the data itself.']},
]

if __name__ == '__main__':
    open(OUT, 'w').write(build())
    print('wrote', OUT)
