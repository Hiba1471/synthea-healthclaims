"""Fail loudly if the care-type ladder has drifted between its three homes.

    python3 tools/check_care_type_ladder.py

The ladder that maps a condition name to a care type is duplicated in three
places, because three different consumers need it and none of them can call
the others:

    sql/analysis/q2_patient_cost_by_care_type.sql   source of truth; built the
                                                    CSV the HTML report reads
    sql/ddl/v_claims_tx_with_caretype.sql           the Power BI view
    dashboard/generators/dashboard_data.py          the dashboard drill-down

Drift between them is silent -- no query errors, no exception, just three
artefacts quietly disagreeing about where money sits. This compares all three
and exits non-zero if any branch, keyword or ORDER differs. Order is checked
because CASE stops at the first match: dental must be tested before infections
or "infection of tooth" changes category.
"""
import re
import sys

SQL_SOURCE = 'sql/analysis/q2_patient_cost_by_care_type.sql'
SQL_VIEW = 'sql/ddl/v_claims_tx_with_caretype.sql'
PY_RULES = 'dashboard/generators/dashboard_data.py'


def norm(pattern):
    """Strip the surrounding .* wildcards, keeping spaces INSIDE keywords.

    An earlier version collapsed all whitespace to absorb line wrapping. That
    also welded "polyp of colon" into "polypofcolon" and reported four false
    drifts, so only the leading/trailing wildcards come off here.
    """
    return pattern.strip().strip('.*').strip()


def from_sql(path):
    s = open(path).read()
    pairs = re.findall(r"REGEXP\s+'([^']+)'\s*\n?\s*THEN\s+'([^']+)'", s, re.S)
    out = [(norm(p), label) for p, label in pairs]
    tail = re.search(r"ELSE\s+'([^']+)'\s*\n?\s*END AS care_type", s)
    if tail:
        out.append(('<ELSE>', tail.group(1)))
    return out


def from_py(path):
    s = open(path).read()
    block = re.search(r'CARE_TYPE_RULES = \[(.*?)\n\]', s, re.S).group(1)
    pairs = re.findall(r"\(r'((?:[^']|'(?!\s*,))*)',\s*\n?\s*'([^']+)'\)", block, re.S)
    # Python adjacent-string concatenation:  r'...(a|b|'  \n  r'c|d)'
    out = [(norm(re.sub(r"'\s*\n\s*r'", '', p)), label) for p, label in pairs]
    out.append(('<ELSE>', 'Other'))  # the function's fallthrough return
    return out


def main():
    ladders = {
        'analysis SQL': from_sql(SQL_SOURCE),
        'Power BI view': from_sql(SQL_VIEW),
        'dashboard py': from_py(PY_RULES),
    }
    ref_name, ref = 'analysis SQL', ladders['analysis SQL']
    print('%-16s %s branches' % (ref_name, len(ref)))

    failed = False
    for name, other in ladders.items():
        if name == ref_name:
            continue
        print('%-16s %s branches' % (name, len(other)))
        for i in range(max(len(ref), len(other))):
            a = ref[i] if i < len(ref) else ('<missing>', '<missing>')
            b = other[i] if i < len(other) else ('<missing>', '<missing>')
            if a != b:
                failed = True
                print('  DRIFT at branch %d vs %s' % (i + 1, ref_name))
                print('    %-14s %s -> %s' % (ref_name, a[0][:60], a[1]))
                print('    %-14s %s -> %s' % (name, b[0][:60], b[1]))

    print('\n%s' % ('DRIFT DETECTED - fix before trusting any care-type figure'
                    if failed else
                    'OK - all three ladders identical, order included'))
    return 1 if failed else 0


if __name__ == '__main__':
    sys.exit(main())
