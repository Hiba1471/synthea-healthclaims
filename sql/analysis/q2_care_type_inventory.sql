-- =====================================================================
-- CARE TYPE INVENTORY: what the care types are, and what is inside each.
--
-- Four browsing queries for checking the grouping rather than reporting on
-- it. q2_care_type_report_from_view.sql has the money; this one answers
-- "what did the ladder actually do to my 185 conditions".
--
-- Run whichever part you need; they are independent.
--
-- Reads V_CLAIMS_TX_WITH_CARETYPE, so the scope filter is already applied.
-- =====================================================================


-- ---------------------------------------------------------------------
-- 1. THE LIST. Every care type, how many conditions landed in it, and what
--    it carries. Expect 16 rows: the 14 keyword branches, 'Other', and
--    'No diagnosis on claim'.
-- ---------------------------------------------------------------------
SELECT
    CARE_TYPE                                      AS "Type of care",
    COUNT(DISTINCT PRIMARY_CONDITION)              AS "Conditions in it",
    COUNT(DISTINCT PATIENT_ID)                     AS "People affected",
    ROUND(SUM(BILLED_AMOUNT))                      AS "Total billed",
    ROUND(100 * SUM(BILLED_AMOUNT)
          / SUM(SUM(BILLED_AMOUNT)) OVER (), 1)    AS "% of all billed"
FROM SYNTHEA_HEALTHCLAIMS.PUBLIC.V_CLAIMS_TX_WITH_CARETYPE
GROUP BY CARE_TYPE
ORDER BY SUM(BILLED_AMOUNT) DESC;


-- ---------------------------------------------------------------------
-- 2. THE MAPPING. Every condition and the care type it was put in, biggest
--    first inside each group. This is the table to scan when a category
--    looks wrong -- roughly 185 rows.
-- ---------------------------------------------------------------------
SELECT
    CARE_TYPE                                      AS "Type of care",
    PRIMARY_CONDITION                              AS "Condition",
    ROUND(SUM(BILLED_AMOUNT))                      AS "Total billed",
    COUNT(DISTINCT PATIENT_ID)                     AS "People affected",
    ROW_NUMBER() OVER (PARTITION BY CARE_TYPE
                       ORDER BY SUM(BILLED_AMOUNT) DESC)
                                                   AS "Rank in its care type"
FROM SYNTHEA_HEALTHCLAIMS.PUBLIC.V_CLAIMS_TX_WITH_CARETYPE
WHERE PRIMARY_CONDITION IS NOT NULL
GROUP BY CARE_TYPE, PRIMARY_CONDITION
ORDER BY CARE_TYPE, SUM(BILLED_AMOUNT) DESC;


-- ---------------------------------------------------------------------
-- 3. THE 'OTHER' BUCKET -- the query worth running first.
--
--    These conditions matched none of the 14 keyword sets. It is the
--    largest group by COUNT (38 conditions) while being the smallest by
--    money (~$91M), and it is where a miscategorised condition hides: if a
--    care type looks light, its conditions are probably sitting here.
--
--    Anything in this list with a real clinical home means the ladder needs
--    another keyword. Add it to ALL THREE copies of the ladder, then run
--    tools/check_care_type_ladder.py to confirm they still agree.
-- ---------------------------------------------------------------------
SELECT
    PRIMARY_CONDITION                              AS "Condition landed in Other",
    ROUND(SUM(BILLED_AMOUNT))                      AS "Total billed",
    COUNT(DISTINCT PATIENT_ID)                     AS "People affected",
    ROUND(SUM(BILLED_AMOUNT)
          / NULLIF(COUNT(DISTINCT PATIENT_ID), 0)) AS "Billed per person"
FROM SYNTHEA_HEALTHCLAIMS.PUBLIC.V_CLAIMS_TX_WITH_CARETYPE
WHERE CARE_TYPE = 'Other'
GROUP BY PRIMARY_CONDITION
ORDER BY SUM(BILLED_AMOUNT) DESC;


-- ---------------------------------------------------------------------
-- 4. ORDER-SENSITIVITY CHECK. The CASE stops at the first match, so a
--    condition whose name hits two branches goes to whichever is tested
--    earlier. "Infection of tooth" is the known case -- it contains both
--    'tooth' and 'infection', and dental is tested first on purpose.
--
--    This lists conditions matching more than one branch, with where they
--    ended up. Nothing here is a bug by itself; it shows which rows would
--    move if anyone reorders the ladder.
-- ---------------------------------------------------------------------
WITH conds AS (
    SELECT DISTINCT PRIMARY_CONDITION AS name, CARE_TYPE
    FROM SYNTHEA_HEALTHCLAIMS.PUBLIC.V_CLAIMS_TX_WITH_CARETYPE
    WHERE PRIMARY_CONDITION IS NOT NULL
),
hits AS (
    SELECT
        name,
        CARE_TYPE,
        ARRAY_CONSTRUCT_COMPACT(
            IFF(LOWER(name) REGEXP '.*(gingiv|dental|tooth|teeth|molar|jaw|palatinus|temporomandibular|mandible|alveolitis).*', 'Dental & oral', NULL),
            IFF(LOWER(name) REGEXP '.*(pregnan|miscarriage|ovum|tubal|newborn|antenatal|postnatal).*', 'Maternity', NULL),
            IFF(LOWER(name) REGEXP '.*(malignant|carcinoma|neoplasm|polyp of colon).*', 'Cancer & tumours', NULL),
            -- Mirrors the ladder's own cholecystitis branch, so a gallbladder
            -- infection shows up here as the three-way overlap it really is.
            IFF(LOWER(name) REGEXP '.*cholecystitis.*', 'Infections (other)', NULL),
            IFF(LOWER(name) REGEXP '.*(kidney|renal|cystitis|pyelonephritis|urinary|bladder).*', 'Kidney & urinary', NULL),
            IFF(LOWER(name) REGEXP '.*(heart|stroke|myocardial|atrial|aortic|coronary|hypertension|cardiac|circulat).*', 'Heart & circulation', NULL),
            IFF(LOWER(name) REGEXP '.*(bronchitis|covid|pharyngitis|sinusitis|sore throat|emphysema|asthma|otitis|respiratory|pneumon|influenza).*', 'Respiratory & ENT', NULL),
            IFF(LOWER(name) REGEXP '.*(diabet|obesity|lipid|glycemia|metabolic|triglyceride|osteoporosis|body mass).*', 'Diabetes & metabolic', NULL),
            IFF(LOWER(name) REGEXP '.*(drug|alcohol|anxiety|attention deficit|sleep|suicide|overdose|depress|stress).*', 'Mental health & substance use', NULL),
            IFF(LOWER(name) REGEXP '.*(injury|fracture|sprain|laceration|burn|concussion|rupture|dislocation|wound).*', 'Injury & trauma', NULL),
            IFF(LOWER(name) REGEXP '.*allerg.*', 'Allergy & immune', NULL),
            IFF(LOWER(name) REGEXP '.*(seizure|alzheimer|neuropathy|epilep|dementia).*', 'Brain & nervous system', NULL),
            IFF(LOWER(name) REGEXP '.*(sepsis|immunodeficiency|appendicitis|cholecystitis|infection|infective|viral|bacterial).*', 'Infections (other)', NULL),
            IFF(LOWER(name) REGEXP '.*(anemia|anaemia).*', 'Blood disorders', NULL),
            IFF(LOWER(name) REGEXP '.*pain.*', 'Chronic pain', NULL)
        ) AS matched
    FROM conds
)
SELECT
    name                                           AS "Condition",
    CARE_TYPE                                      AS "Went to (first match wins)",
    ARRAY_SIZE(matched)                            AS "Branches it matched",
    ARRAY_TO_STRING(matched, ', ')                 AS "All branches matched"
FROM hits
WHERE ARRAY_SIZE(matched) > 1
ORDER BY ARRAY_SIZE(matched) DESC, name;
