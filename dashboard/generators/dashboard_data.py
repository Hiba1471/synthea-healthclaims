"""Build the JSON payload behind dashboard/claims_dashboard.html.

Every number here comes from a saved result CSV in sql/results/, which is itself
the output of a query in sql/analysis/. Nothing is invented and nothing is
rescaled.

The one derived step is the condition -> care type mapping used by the Chart 2
and Chart 4A drill-downs. sql/results/ holds condition-level money
(q2_oop_by_condition) and care-type-level money (q2_patient_cost_by_care_type)
but no file joining the two, so CARE_TYPE_RULES below reproduces the regex
ladder from q2_patient_cost_by_care_type.sql EXACTLY, in the same order --
dental first, so "infection of tooth" lands in dental rather than infections.
If that CASE expression changes, change this list with it.

reconcile() checks the mapping against the care-type totals and prints the
per-category drift. It is not a formality: the two sources count patients
differently (a member with two conditions in a category is counted once by the
care-type query and twice here), so patient counts are expected to diverge
while billed dollars should not.
"""
import csv
import json
import os
import re

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
RESULTS = os.path.join(ROOT, 'sql', 'results')
OUT = os.path.join(ROOT, 'dashboard', 'dashboard_data.json')

# Order matters and mirrors the CASE ladder in q2_patient_cost_by_care_type.sql.
CARE_TYPE_RULES = [
    (r'(gingiv|dental|tooth|teeth|molar|jaw|palatinus|temporomandibular|mandible|alveolitis)',
     'Dental & oral'),
    (r'(pregnan|miscarriage|ovum|tubal|newborn|antenatal|postnatal)', 'Maternity'),
    (r'(malignant|carcinoma|neoplasm|polyp of colon)', 'Cancer & tumours'),
    # "cholecystitis" contains "cystitis"; tested before the kidney branch so a
    # gallbladder infection does not land in Kidney & urinary. Mirrors the same
    # guard in both SQL ladders.
    (r'cholecystitis', 'Infections (other)'),
    (r'(kidney|renal|cystitis|pyelonephritis|urinary|bladder)', 'Kidney & urinary'),
    (r'(heart|stroke|myocardial|atrial|aortic|coronary|hypertension|cardiac|circulat)',
     'Heart & circulation'),
    (r'(bronchitis|covid|pharyngitis|sinusitis|sore throat|emphysema|asthma|otitis|'
     r'respiratory|pneumon|influenza)', 'Respiratory & ENT'),
    (r'(diabet|obesity|lipid|glycemia|metabolic|triglyceride|osteoporosis|body mass)',
     'Diabetes & metabolic'),
    (r'(drug|alcohol|anxiety|attention deficit|sleep|suicide|overdose|depress|stress)',
     'Mental health & substance use'),
    (r'(injury|fracture|sprain|laceration|burn|concussion|rupture|dislocation|wound)',
     'Injury & trauma'),
    (r'allerg', 'Allergy & immune'),
    (r'(seizure|alzheimer|neuropathy|epilep|dementia)', 'Brain & nervous system'),
    (r'(sepsis|immunodeficiency|appendicitis|cholecystitis|infection|infective|viral|bacterial)',
     'Infections (other)'),
    (r'(anemia|anaemia)', 'Blood disorders'),
    (r'pain', 'Chronic pain'),
]


def classify(name):
    low = name.lower()
    for pattern, label in CARE_TYPE_RULES:
        if re.search(pattern, low):
            return label
    return 'Other'


def rows(filename):
    with open(os.path.join(RESULTS, filename)) as fh:
        return list(csv.DictReader(fh))


def num(value):
    """CSV numbers arrive as strings, sometimes empty, sometimes with $ or %."""
    if value is None:
        return None
    cleaned = value.strip().replace('$', '').replace(',', '').replace('%', '')
    if cleaned == '':
        return None
    return float(cleaned)


def chart1_trend():
    """Total billed and cost per member by year, plus the same split by payer type.

    Source: q2_who_pays_by_year_2020_2024.csv, cuts '1. Overall' and
    '2. Payer type'. Cost per member is the file's own 'Billed per Patient',
    not a division done here.
    """
    data = rows('q2_who_pays_by_year_2020_2024.csv')
    overall = [{'year': int(r['Year']),
                'billed': num(r['Total Billed']),
                'members': int(r['Patients']),
                'billed_per_member': num(r['Billed per Patient']),
                'member_paid': num(r['Paid by Patient']),
                'member_share': num(r['% Patient'])}
               for r in data if r['Cut'] == '1. Overall']

    by_payer = {}
    for r in data:
        if r['Cut'] != '2. Payer type':
            continue
        by_payer.setdefault(r['Segment'], []).append(
            {'year': int(r['Year']),
             'billed': num(r['Total Billed']),
             'members': int(r['Patients']),
             'billed_per_member': num(r['Billed per Patient']),
             'member_paid': num(r['Paid by Patient']),
             'member_share': num(r['% Patient'])})
    for series in by_payer.values():
        series.sort(key=lambda d: d['year'])

    return {'overall': sorted(overall, key=lambda d: d['year']), 'by_payer': by_payer}


def chart2_care_types():
    """Care types with member-paid share, and the conditions inside each.

    Care-type money: q2_patient_cost_by_care_type_2020_2024.csv.
    Condition money: q2_oop_by_condition_2020_2024.csv, mapped by classify().
    """
    care = []
    for r in rows('q2_patient_cost_by_care_type_2020_2024.csv'):
        care.append({
            'care_type': r['Type of care'],
            'billed': num(r['Total bill']),
            'member_paid': num(r['Paid by patients over 5 years']),
            'member_share': num(r['% the bill patients pay'.replace('the', 'of the')]
                                if '% of the bill patients pay' in r
                                else r['% of the bill patients pay']),
            'members': int(num(r['People affected'])),
            'conditions_grouped': int(num(r['Conditions grouped here'])),
            'cost_per_member': num(r['Total cost per person over 5 years']),
            'share_commercial': num(r['% patients pay - Commercial']),
            'share_government': num(r['% patients pay - Government']),
        })
    care.sort(key=lambda d: -d['billed'])

    conditions = []
    for r in rows('q2_oop_by_condition_2020_2024.csv'):
        name = r['Condition']
        conditions.append({
            'condition': name,
            'care_type': classify(name),
            'billed': num(r['Total Billed']),
            'member_paid': num(r['Patient Out of Pocket']),
            'member_share': num(r['% of Bill Patient Pays']),
            'members': int(num(r['Patients'])),
            'oop_per_member': num(r['Out of Pocket per Patient']),
        })
    conditions.sort(key=lambda d: -d['billed'])
    return {'care_types': care, 'conditions': conditions}


def chart3_payer_share():
    """Member-paid share by payer type by year: q2_who_pays_by_year, payer cut."""
    series = {}
    for r in rows('q2_who_pays_by_year_2020_2024.csv'):
        if r['Cut'] != '2. Payer type':
            continue
        series.setdefault(r['Segment'], []).append(
            {'year': int(r['Year']), 'member_share': num(r['% Patient']),
             'member_paid_per_member': num(r['Patient Paid per Patient'])})
    for points in series.values():
        points.sort(key=lambda d: d['year'])
    return series


def chart4_concentration():
    """Cumulative-share curves for care types, facilities and members.

    Facilities: q3_top_entities_2020_2024.csv already carries a running %.
    Members: q3_lorenz_points_2020_2024.csv, the Patients grain.
    Care types: accumulated here from the care-type billed totals.
    Headline thresholds: q3_concentration_2020_2024.csv.
    """
    care = chart2_care_types()['care_types']
    total_care = sum(c['billed'] for c in care)
    care_curve, running = [], 0.0
    for i, c in enumerate(care, 1):
        running += c['billed']
        care_curve.append({'rank': i, 'name': c['care_type'], 'billed': c['billed'],
                           'cumulative_pct': round(100 * running / total_care, 2)})

    facilities = []
    for r in rows('q3_top_entities_2020_2024.csv'):
        if r['Entity Type'] != 'Hospital':
            continue
        facilities.append({'rank': int(num(r['Rank'])), 'name': r['Name'],
                           'billed': num(r['Total Billed']),
                           'cumulative_pct': num(r['Running % of Type Spend']),
                           'members': int(num(r['Patients']))})
    facilities.sort(key=lambda d: d['rank'])

    members = [{'pct_group': num(r['Pct Entities']), 'cumulative_pct': num(r['Pct Spend'])}
               for r in rows('q3_lorenz_points_2020_2024.csv') if r['Grain'] == 'Patients']
    members.sort(key=lambda d: d['pct_group'])

    headline = {}
    for r in rows('q3_concentration_2020_2024.csv'):
        headline[r['Ranked by']] = {
            'population': int(num(r['How many exist'])),
            'top1': num(r['Priciest 1% run up this % of spend']),
            'top5': num(r['Priciest 5% run up this % of spend']),
            'top10': num(r['Priciest 10% run up this % of spend']),
            'pct_for_half': num(r['% of them needed to reach half the spend']),
            'count_for_half': int(num(r['= this many of them'])),
        }
    return {'care_curve': care_curve, 'facilities': facilities[:20],
            'members': members, 'headline': headline}


def chart5_bubble():
    """One bubble per care type: members, median out-of-pocket, billed, share.

    Median OOP: q2_oop_percentiles_by_care_type_2020_2024.csv.
    Billed and share: the care-type file, joined on care type name.
    """
    money = {c['care_type']: c for c in chart2_care_types()['care_types']}
    out = []
    for r in rows('q2_oop_percentiles_by_care_type_2020_2024.csv'):
        name = r['Type of care']
        if name not in money:
            continue
        out.append({
            'care_type': name,
            'members': int(num(r['People affected'])),
            'median_oop': num(r['Median OOP over 5 years']),
            'p75_oop': num(r['P75 OOP over 5 years']),
            'p90_oop': num(r['P90 OOP over 5 years']),
            'billed': money[name]['billed'],
            'member_share': money[name]['member_share'],
        })
    out.sort(key=lambda d: -d['billed'])
    return out


def monthly():
    """Monthly cuts from q4_monthly_trends.sql, if that query has been run yet.

    Returns None when the result file is absent -- every other result in
    sql/results/ is yearly, so this is the one input that has to be produced
    against the live warehouse before the dashboard can show a month axis.
    The caller renders the yearly view and says so rather than inventing months.
    """
    path = os.path.join(RESULTS, 'q4_monthly_trends_2020_2024.csv')
    if not os.path.exists(path):
        return None
    out = {'overall': [], 'by_payer': {}, 'by_care': {}}
    for r in rows('q4_monthly_trends_2020_2024.csv'):
        point = {
            'month': r['Month'],
            'year': int(num(r['Year'])),
            'billed': num(r['Total billed']),
            'member_paid': num(r['Paid by members']),
            'payer_paid': num(r['Paid by insurer']),
            'member_share': num(r['% of the bill members pay']),
            'members': int(num(r['People affected'])),
            'billed_per_member': num(r['Billed per person']),
        }
        cut, seg = r['Cut'], r['Segment']
        if cut.startswith('1.'):
            out['overall'].append(point)
        elif cut.startswith('2.'):
            out['by_payer'].setdefault(seg, []).append(point)
        elif cut.startswith('3.'):
            out['by_care'].setdefault(seg, []).append(point)
    out['overall'].sort(key=lambda d: d['month'])
    for group in (out['by_payer'], out['by_care']):
        for series in group.values():
            series.sort(key=lambda d: d['month'])
    return out


def check_monthly(payload):
    """Monthly totals must roll up to the yearly figures already published."""
    m = payload.get('monthly')
    if not m:
        print('monthly: q4_monthly_trends_2020_2024.csv not present -- '
              'dashboard will show the yearly axis')
        return
    yearly = {d['year']: d['billed'] for d in payload['chart1']['overall']}
    rolled = {}
    for p in m['overall']:
        rolled[p['year']] = rolled.get(p['year'], 0) + p['billed']
    print('\n%-6s %18s %18s %8s' % ('YEAR', 'YEARLY FILE', 'MONTHLY ROLLED', 'DRIFT'))
    for y in sorted(yearly):
        a, b = yearly[y], rolled.get(y, 0)
        print('%-6s %18.0f %18.0f %7.3f%%'
              % (y, a, b, 100 * (b - a) / a if a else 0))
    print('months: %d (expect 60)' % len(m['overall']))


def reconcile(payload):
    """Compare the derived condition->care type mapping against the care-type file.

    Billed dollars should line up closely. Patient counts are NOT expected to:
    the care-type query counts a member once per care type, while summing
    conditions counts them once per condition. Printed, not silenced.
    """
    care = {c['care_type']: c['billed'] for c in payload['chart2']['care_types']}
    derived = {}
    for c in payload['chart2']['conditions']:
        derived[c['care_type']] = derived.get(c['care_type'], 0) + c['billed']

    print('%-32s %16s %16s %8s' % ('CARE TYPE', 'FROM CARE FILE', 'FROM CONDITIONS', 'DRIFT'))
    worst = 0.0
    for name in sorted(care, key=lambda k: -care[k]):
        a, b = care[name], derived.get(name, 0.0)
        drift = 100 * (b - a) / a if a else 0.0
        worst = max(worst, abs(drift))
        print('%-32s %16.0f %16.0f %7.2f%%' % (name[:32], a, b, drift))
    print('\nlargest absolute drift: %.2f%%' % worst)
    return worst


def build():
    payload = {
        'chart1': chart1_trend(),
        'chart2': chart2_care_types(),
        'chart3': chart3_payer_share(),
        'chart4': chart4_concentration(),
        'chart5': chart5_bubble(),
        'monthly': monthly(),
    }
    payload['meta'] = {
        'window': '2020-2024',
        'total_billed': payload['chart4']['headline']['Patients']['population'] and
                        sum(y['billed'] for y in payload['chart1']['overall']),
        'members': payload['chart4']['headline']['Patients']['population'],
        'facilities': payload['chart4']['headline']['Organisations']['population'],
        'care_types': len(payload['chart2']['care_types']),
        'conditions': len(payload['chart2']['conditions']),
    }
    return payload


if __name__ == '__main__':
    data = build()
    reconcile(data)
    check_monthly(data)
    with open(OUT, 'w') as fh:
        json.dump(data, fh, separators=(',', ':'), sort_keys=True)
    print('\nwrote %s (%.0f KB)' % (OUT, os.path.getsize(OUT) / 1024))
