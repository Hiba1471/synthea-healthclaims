-- =====================================================================
-- Q3 FOLLOW-UP: what are patients actually seen for, by kind of site?
--
-- The 12 VA-named sites bill ordinary prices but see each patient 24-54 times
-- against a median of 4.5. Two readings fit that equally well from the outside:
--
--   GOOD ACCESS. Patients are enrolled in continuous management of chronic
--   conditions and come in on a schedule. Many visits is the system working.
--
--   UNRESOLVED PROBLEMS. Patients keep coming back for the same complaint
--   because it is not being fixed. Many visits is the system failing.
--
-- The discriminator is NOT the number of visits, which is identical under both.
-- It is what the visits are FOR:
--
--   Under good access, a patient's visits spread across several conditions and
--   lean chronic -- diabetes, heart, mental health -- because someone managing
--   your whole health touches many things on a schedule.
--
--   Under unresolved care, visits concentrate on ONE condition per patient and
--   lean acute -- infections, injury, pain -- the same complaint recurring.
--
-- So this query reports, for VA sites against everywhere else:
--   1. the care-type mix, to see whether it leans chronic or acute, and
--   2. distinct conditions per patient and repeat visits per condition, which
--      is the actual test.
--
-- WHAT THIS CANNOT SETTLE. Synthea generates encounters from condition modules
-- on fixed schedules; it does not model care quality, treatment failure or
-- patient dissatisfaction. A "return visit" here is the generator following its
-- own script, not a person whose problem went unfixed. So this can show which
-- STORY the data is consistent with, and it can rule one out, but it cannot
-- establish that real veterans' care is good or bad. Do not let the answer
-- travel further than that.
--
-- The same question runs for HOSPICE & NURSING sites, the other group singled
-- out in dashboard/two_ways_expensive.html. There the puzzle is the opposite --
-- 1.0-2.7 visits per patient, not fifty -- and the reading to test is that one
-- visit is a whole multi-week stay rather than an appointment.
--
-- Both groups are matched on NAME; nothing in the data marks a facility as a VA
-- site or a hospice. Same patterns as
-- dashboard/generators/q3_two_ways_expensive.py; keep them in step.
--
-- Results: sql/results/q3_site_group_conditions_2020_2024.csv
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
