"""Draw the billed-by-plan-type donut, with the total in the centre.

    python3 dashboard/generators/donut_chart.py

Writes dashboard/donut_billed_by_payer.png (and .svg) in light and dark.
The centre label is the thing Power BI's native donut cannot do without
overlaying a Card visual; here it is just text drawn at the origin.

Numbers come from dashboard/dashboard_data.json so this stays in step with the
rest of the dashboard rather than carrying its own copy. Run dashboard_data.py
first if the results have changed.

Three segments, which is why a donut is the right form at all: part-to-whole
reads at a glance up to about six slices and stops working past that. If you
ever swap PAYER_TYPE for PAYER_NAME you get ten slices -- use a bar chart then.
Every slice is labelled with its name, dollars and share, so colour is never
carrying the meaning on its own.
"""
import json
import math
import os

import matplotlib
matplotlib.use('Agg')  # no display needed; write straight to file
import matplotlib.pyplot as plt

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
DATA = os.path.join(ROOT, 'dashboard', 'dashboard_data.json')
OUTDIR = os.path.join(ROOT, 'dashboard')

# Validated categorical slots 1-3, used unchanged. These three are the documented
# all-pairs-safe subset, which is exactly the cap a pie/donut needs.
SLICE_COLORS = {
    'Government': '#2a78d6',
    'Commercial': '#eb6834',
    'Self-Pay / Uninsured': '#1baf7a',
}

THEMES = {
    'light': {'bg': '#fcfcfb', 'ink': '#0b0b0b', 'ink2': '#52514e',
              'muted': '#898781', 'ring': '#fcfcfb'},
    'dark': {'bg': '#1a1a19', 'ink': '#ffffff', 'ink2': '#c3c2b7',
             'muted': '#898781', 'ring': '#1a1a19'},
}


def money(v):
    """$99.11B / $434.6M -- the same scale-and-suffix the dashboard uses."""
    a = abs(v)
    if a >= 1e9:
        return '$%.2fB' % (v / 1e9)
    if a >= 1e6:
        return '$%.1fM' % (v / 1e6)
    if a >= 1e3:
        return '$%.0fK' % (v / 1e3)
    return '$%.0f' % v


def load_slices():
    """Billed per payer type, summed across the five years, largest first."""
    with open(DATA) as fh:
        payload = json.load(fh)
    out = []
    for name, series in payload['chart1']['by_payer'].items():
        out.append({'name': name, 'value': sum(y['billed'] for y in series)})
    out.sort(key=lambda d: -d['value'])
    return out


def draw(slices, theme_name, filename):
    t = THEMES[theme_name]
    total = sum(s['value'] for s in slices)

    fig, ax = plt.subplots(figsize=(7.2, 5.2), dpi=200)
    fig.subplots_adjust(top=0.86)
    fig.patch.set_facecolor(t['bg'])
    ax.set_facecolor(t['bg'])

    wedges, _ = ax.pie(
        [s['value'] for s in slices],
        colors=[SLICE_COLORS.get(s['name'], '#999999') for s in slices],
        startangle=90,
        counterclock=False,
        # width sets the hole; the 2px ring in the surface colour keeps
        # adjacent slices from touching, same spacer rule as the HTML charts
        wedgeprops={'width': 0.38, 'edgecolor': t['ring'], 'linewidth': 2},
    )

    # ---- centre label: the total, which is why the hole exists ----
    ax.text(0, 0.10, money(total), ha='center', va='center',
            fontsize=23, fontweight='bold', color=t['ink'])
    ax.text(0, -0.12, 'total billed', ha='center', va='center',
            fontsize=10.5, color=t['muted'])
    ax.text(0, -0.28, '2020–2024', ha='center', va='center',
            fontsize=9, color=t['muted'])

    # ---- direct labels with leader lines, so no legend is needed ----
    for wedge, s in zip(wedges, slices):
        ang = (wedge.theta2 + wedge.theta1) / 2.0
        rad = ang * 3.14159265 / 180.0
        x, y = math.cos(rad), math.sin(rad)
        right = x >= 0
        ax.annotate(
            '%s\n%s  ·  %.1f%%' % (s['name'].replace(' / Uninsured', ''),
                                   money(s['value']), 100 * s['value'] / total),
            xy=(0.86 * x, 0.86 * y),
            xytext=(1.32 * (1 if right else -1), 1.12 * y),
            ha='left' if right else 'right', va='center',
            fontsize=10, color=t['ink2'], linespacing=1.45,
            arrowprops={'arrowstyle': '-', 'color': t['muted'],
                        'linewidth': 0.9,
                        'connectionstyle': 'angle,angleA=0,angleB=%d' % ang},
        )

    # Title and subtitle are placed on the FIGURE, not the axes: ax.set_title's
    # pad and an axes-coordinate subtitle both resolve to nearly the same height
    # and collide. Figure coordinates give each one its own line.
    fig.text(0.04, 0.97, 'Billed by plan type', fontsize=14, fontweight='bold',
             color=t['ink'], va='top')
    fig.text(0.04, 0.915, 'Where five years of spend sits across the lines of business',
             fontsize=10, color=t['muted'], va='top')

    ax.set_xlim(-1.9, 1.9)
    ax.set_ylim(-1.35, 1.35)
    ax.set_aspect('equal')
    ax.axis('off')

    for ext in ('png', 'svg'):
        path = os.path.join(OUTDIR, '%s.%s' % (filename, ext))
        fig.savefig(path, facecolor=t['bg'], bbox_inches='tight', pad_inches=0.3)
        print('wrote %s' % path)
    plt.close(fig)


if __name__ == '__main__':
    data = load_slices()
    total = sum(s['value'] for s in data)
    print('%-24s %18s %8s' % ('PLAN TYPE', 'BILLED', 'SHARE'))
    for s in data:
        print('%-24s %18s %7.1f%%'
              % (s['name'], '{:,.0f}'.format(s['value']), 100 * s['value'] / total))
    print('%-24s %18s' % ('TOTAL', '{:,.0f}'.format(total)))
    print()
    draw(data, 'light', 'donut_billed_by_payer')
    draw(data, 'dark', 'donut_billed_by_payer_dark')
