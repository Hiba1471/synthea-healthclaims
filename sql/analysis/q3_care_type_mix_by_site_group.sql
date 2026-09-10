-- =====================================================================
-- Q3 follow-up: the 12 VA-named sites see patients 24-54 times against a
-- median of 4.5. Is that good access (continuous chronic management) or
-- unresolved problems (the same complaint recurring)? The discriminator
-- is not visit count but what visits are FOR: good access spreads across
-- several chronic conditions, unresolved care concentrates on one acute
-- complaint per patient. Reports care-type mix, distinct conditions per
-- patient and repeat visits per condition, for VA sites vs. everywhere
-- else, then the same test for hospice/nursing sites (the opposite
-- puzzle: 1.0-2.7 visits, where one "visit" may be a multi-week stay).
--
-- CANNOT SETTLE: Synthea generates encounters from fixed condition
-- schedules, not care quality or treatment failure, so this shows which
-- story the data is consistent with and can rule one out -- it cannot
-- establish that real veterans' care is good or bad.
--
-- Both groups are matched on NAME only; keep in step with
-- dashboard/generators/q3_two_ways_expensive.py.
-- =====================================================================

WITH base AS (
    SELECT CLAIM_ID, PATIENT_ID, ENCOUNTER_ID, BILLED_AMOUNT
    FROM SYNTHEA_HEALTHCLAIMS.PUBLIC.V_CLAIMS_TX_CLEAN
    WHERE NOT IS_ADMIN_NOISE_CODE
      AND PROCEDURECODE IS NOT NULL
      AND BILLED_AMOUNT > 0
),
sited AS (
    SELECT
        b.PATIENT_ID, b.CLAIM_ID, b.ENCOUNTER_ID, b.BILLED_AMOUNT,
        CASE WHEN o.NAME ILIKE '%vet center%'
               OR o.NAME ILIKE '%va medical%'
               OR o.NAME ILIKE '%auburn gresham%'
               OR o.NAME ILIKE '%lakeside clinic%'
               OR o.NAME ILIKE '%community based outpatient%'
             THEN 'Veterans sites'
             WHEN o.NAME ILIKE '%hospice%'
               OR o.NAME ILIKE '%convalescent%'
               OR o.NAME ILIKE '%palliative%'
               OR o.NAME ILIKE '%nursing home%'
               OR o.NAME ILIKE '%home care%'
             THEN 'Hospice & nursing'
             ELSE 'Everywhere else' END AS site_group
    FROM base b
    JOIN SYNTHETIC_HEALTHCARE_DATA_CLINICAL_AND_CLAIMS.SILVER.ENCOUNTERS e
      ON b.ENCOUNTER_ID = e.ENCOUNTER_ID
    JOIN SYNTHETIC_HEALTHCARE_DATA_CLINICAL_AND_CLAIMS.SILVER.ORGANIZATIONS o
      ON e.ORGANIZATION_ID = o.ORGANIZATION_ID
),
claim_condition AS (
    SELECT c.CLAIM_ID,
           CASE WHEN d1.IS_CONDITION THEN c.DIAGNOSIS1
                WHEN d2.IS_CONDITION THEN c.DIAGNOSIS2 END AS condition_code
    FROM SYNTHETIC_HEALTHCARE_DATA_CLINICAL_AND_CLAIMS.SILVER.CLAIMS c
    LEFT JOIN SYNTHEA_HEALTHCLAIMS.PUBLIC.CODE_DICTIONARY d1 ON c.DIAGNOSIS1 = d1.CODE
    LEFT JOIN SYNTHEA_HEALTHCLAIMS.PUBLIC.CODE_DICTIONARY d2 ON c.DIAGNOSIS2 = d2.CODE
),
classified AS (
    SELECT s.site_group, s.PATIENT_ID, s.ENCOUNTER_ID, s.BILLED_AMOUNT,
           cc.condition_code,
        CASE
            WHEN LOWER(d.DESCRIPTION) REGEXP '.*(gingiv|dental|tooth|teeth|molar|jaw|palatinus|temporomandibular|mandible|alveolitis).*'
                THEN 'Dental & oral'
            WHEN LOWER(d.DESCRIPTION) REGEXP '.*(pregnan|miscarriage|ovum|tubal|newborn|antenatal|postnatal).*'
                THEN 'Maternity'
            WHEN LOWER(d.DESCRIPTION) REGEXP '.*(malignant|carcinoma|neoplasm|polyp of colon).*'
                THEN 'Cancer & tumours'
            -- "cholecystitis" contains the substring "cystitis", so the Kidney &
            -- urinary branch below would otherwise claim a gallbladder infection.
            -- Tested first and routed where it belongs.
            WHEN LOWER(d.DESCRIPTION) REGEXP '.*cholecystitis.*'
                THEN 'Infections (other)'
            WHEN LOWER(d.DESCRIPTION) REGEXP '.*(kidney|renal|cystitis|pyelonephritis|urinary|bladder).*'
                THEN 'Kidney & urinary'
            WHEN LOWER(d.DESCRIPTION) REGEXP '.*(heart|stroke|myocardial|atrial|aortic|coronary|hypertension|cardiac|circulat).*'
                THEN 'Heart & circulation'
            WHEN LOWER(d.DESCRIPTION) REGEXP '.*(bronchitis|covid|pharyngitis|sinusitis|sore throat|emphysema|asthma|otitis|respiratory|pneumon|influenza).*'
                THEN 'Respiratory & ENT'
            WHEN LOWER(d.DESCRIPTION) REGEXP '.*(diabet|obesity|lipid|glycemia|metabolic|triglyceride|osteoporosis|body mass).*'
                THEN 'Diabetes & metabolic'
            WHEN LOWER(d.DESCRIPTION) REGEXP '.*(drug|alcohol|anxiety|attention deficit|sleep|suicide|overdose|depress|stress).*'
                THEN 'Mental health & substance use'
            WHEN LOWER(d.DESCRIPTION) REGEXP '.*(injury|fracture|sprain|laceration|burn|concussion|rupture|dislocation|wound).*'
                THEN 'Injury & trauma'
            WHEN LOWER(d.DESCRIPTION) REGEXP '.*allerg.*'
                THEN 'Allergy & immune'
            WHEN LOWER(d.DESCRIPTION) REGEXP '.*(seizure|alzheimer|neuropathy|epilep|dementia).*'
                THEN 'Brain & nervous system'
            WHEN LOWER(d.DESCRIPTION) REGEXP '.*(sepsis|immunodeficiency|appendicitis|cholecystitis|infection|infective|viral|bacterial).*'
                THEN 'Infections (other)'
            WHEN LOWER(d.DESCRIPTION) REGEXP '.*(anemia|anaemia).*'
                THEN 'Blood disorders'
            WHEN LOWER(d.DESCRIPTION) REGEXP '.*pain.*'
                THEN 'Chronic pain'
            ELSE 'Other'
        END AS care_type
    FROM sited s
    JOIN claim_condition cc ON s.CLAIM_ID = cc.CLAIM_ID
    JOIN SYNTHEA_HEALTHCLAIMS.PUBLIC.CODE_DICTIONARY d ON cc.condition_code = d.CODE
    WHERE cc.condition_code IS NOT NULL
),
-- how concentrated is one patient's care on a single condition?
-- visits_per_condition is the discriminator: high means the same complaint
-- recurring, low means visits spread across a patient's whole health.
per_patient AS (
    SELECT site_group, PATIENT_ID,
           COUNT(DISTINCT condition_code) AS conditions_seen,
           COUNT(DISTINCT ENCOUNTER_ID)   AS visits
    FROM classified
    GROUP BY site_group, PATIENT_ID
),
patient_summary AS (
    SELECT site_group,
           AVG(conditions_seen)                     AS avg_conditions,
           AVG(visits)                              AS avg_visits,
           AVG(visits * 1.0 / conditions_seen)      AS avg_visits_per_condition
    FROM per_patient
    GROUP BY site_group
)
SELECT
    c.site_group                                          AS "Site group",
    c.care_type                                           AS "Type of care",
    COUNT(DISTINCT c.ENCOUNTER_ID)                        AS "Visits",
    ROUND(100.0 * COUNT(DISTINCT c.ENCOUNTER_ID)
          / SUM(COUNT(DISTINCT c.ENCOUNTER_ID))
            OVER (PARTITION BY c.site_group), 1)          AS "% of that group's visits",
    COUNT(DISTINCT c.PATIENT_ID)                          AS "Patients",
    ROUND(SUM(c.BILLED_AMOUNT))                           AS "Billed",
    -- group-level figures, repeated on each row so the CSV reads standalone
    ROUND(MAX(ps.avg_conditions), 2)                      AS "Conditions per patient (group)",
    ROUND(MAX(ps.avg_visits), 1)                          AS "Visits per patient (group)",
    ROUND(MAX(ps.avg_visits_per_condition), 2)            AS "Visits per condition (group)"
FROM classified c
JOIN patient_summary ps ON ps.site_group = c.site_group
GROUP BY c.site_group, c.care_type
ORDER BY c.site_group, "Visits" DESC;
