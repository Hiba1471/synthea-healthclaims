"""Fail loudly if the care-type ladder has drifted between its many homes.

    python3 tools/check_care_type_ladder.py

The ladder that maps a condition name to a care type is copy-pasted into a
dozen-plus files, because each consumer needs it and none of them can call the
others. Drift between them is silent -- no query errors, no exception, just
artefacts quietly disagreeing about where money sits.

This finds EVERY copy by scanning for the ladder itself rather than trusting a
hardcoded list, and exits non-zero if any branch, keyword or ORDER differs.
Order matters because CASE stops at the first match: "cholecystitis" has to be
tested before the kidney branch, or a gallbladder infection is filed as urinary.

An earlier version checked only three files by name. Ten other copies carried
a known bug for weeks while this printed OK, which is why discovery is now
automatic -- a new copy is picked up the moment it is written.
"""
import os
import re
import sys

PY_RULES = 'dashboard/generators/dashboard_data.py'
REFERENCE = 'sql/analysis/q2_patient_cost_by_care_type.sql'
FIRST_LABEL = 'Dental & oral'   # the ladder's first branch, used as an anchor
MARKER = 'pyelonephritis'       # appears only inside the ladder


def norm(pattern):
    """Strip the surrounding .* wildcards, keeping spaces INSIDE keywords.

    An earlier version collapsed all whitespace to absorb line wrapping. That
    also welded "polyp of colon" into "polypofcolon" and reported four false
    drifts, so only the leading/trailing wildcards come off here.
    """
    return pattern.strip().strip('.*').strip()


def _slice(pairs):
    """Keep the ladder itself, dropping any unrelated REGEXP nearby."""
    labels = [lab for _, lab in pairs]
    if FIRST_LABEL not in labels:
        return []
    return pairs[labels.index(FIRST_LABEL):]


def from_sql(path):
    """Both shapes: WHEN ... THEN 'x', and IFF(..., 'x', NULL) inside an array."""
    s = open(path).read()
    pairs = re.findall(r"REGEXP\s+'([^']+)'\s*\n?\s*THEN\s+'([^']+)'", s, re.S)
    pairs += re.findall(r"REGEXP\s+'([^']+)',\s*'([^']+)',\s*NULL", s, re.S)
    return _slice([(norm(p), lab) for p, lab in pairs])


def from_py(path):
    s = open(path).read()
    block = re.search(r'CARE_TYPE_RULES = \[(.*?)\n\]', s, re.S).group(1)
    pairs = re.findall(r"\(r'((?:[^']|'(?!\s*,))*)',\s*\n?\s*'([^']+)'\)", block, re.S)
    # Python adjacent-string concatenation:  r'...(a|b|'  \n  r'c|d)'
    return _slice([(norm(re.sub(r"'\s*\n\s*r'", '', p)), lab) for p, lab in pairs])


def discover():
    """Every file carrying the ladder, found by scanning rather than by list."""
    found = []
    for root, _, files in os.walk('sql'):
        for f in sorted(files):
            if not f.endswith('.sql'):
                continue
            path = os.path.join(root, f)
            if MARKER in open(path).read():
                found.append(path)
    return found


def main():
    ladders = {REFERENCE: from_sql(REFERENCE)}
    for path in discover():
        ladders.setdefault(path, from_sql(path))
    ladders[PY_RULES] = from_py(PY_RULES)

    ref = ladders[REFERENCE]
    print('%s branches in the reference ladder' % len(ref))
    print('%s copies found\n' % len(ladders))

    failed = False
    for name, other in sorted(ladders.items()):
        mark = 'ok  '
        rows = []
        for i in range(max(len(ref), len(other))):
            a = ref[i] if i < len(ref) else ('<missing>', '<missing>')
            b = other[i] if i < len(other) else ('<missing>', '<missing>')
            if a != b:
                failed = True
                mark = 'DRIFT'
                rows.append('    branch %d: expected %s -> %s\n'
                            '               found    %s -> %s'
                            % (i + 1, a[0][:50], a[1], b[0][:50], b[1]))
        print('%-5s %-52s %2d branches' % (mark, name, len(other)))
        for r in rows:
            print(r)

    print('\n%s' % ('DRIFT DETECTED - fix before trusting any care-type figure'
                    if failed else
                    'OK - every copy identical, order included'))
    return 1 if failed else 0


if __name__ == '__main__':
    sys.exit(main())
