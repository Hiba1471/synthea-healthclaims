-- =====================================================================
-- Q3 FOLLOW-UP: which specific conditions bring patients into each kind of site?
--
-- q3_site_group_conditions.sql shows 64.9% of visits at veterans' sites are
-- "Kidney & urinary" against 32.0% everywhere else, and that patients there
-- return 6.31 times per condition against 3.42. Care type is too coarse to say
-- why: that group mixes dialysis with bladder infections (see
-- q2_cap_reversal_diagnosis.sql). This drops to the condition itself.
--
-- The question being settled is whether many visits per patient means good
-- continuous care or problems that never resolve. A third possibility has to
-- be ruled in or out first: that the visit count is neither, and is simply the
-- treatment MODALITY. Dialysis is three sessions a week for life. If the VA
-- sites are dominated by end-stage renal disease, their visit count says
-- nothing about care quality at all -- it says what treatment those patients
-- are on.
--
-- Hospice & nursing sites are included as the third group. Their puzzle is the
-- mirror image: 1.0-2.7 visits per patient at up to $16,030 a "visit". Care type
-- cannot distinguish a genuinely costly admission from a long stay counted once,
-- so the condition and the billed-per-visit column are read together.
--
-- Both groups matched on NAME; nothing in the data marks a facility as either.
-- Same patterns as q3_site_group_conditions.sql and q3_two_ways_expensive.py.
--
-- Results: sql/results/q3_site_group_top_conditions_2020_2024.csv
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
)
SELECT
    s.site_group                                          AS "Site group",
    d.DESCRIPTION                                         AS "Condition",
    COUNT(DISTINCT s.ENCOUNTER_ID)                        AS "Visits",
    ROUND(100.0 * COUNT(DISTINCT s.ENCOUNTER_ID)
          / SUM(COUNT(DISTINCT s.ENCOUNTER_ID))
            OVER (PARTITION BY s.site_group), 1)          AS "% of that group's visits",
    COUNT(DISTINCT s.PATIENT_ID)                          AS "Patients",
    ROUND(COUNT(DISTINCT s.ENCOUNTER_ID) * 1.0
          / NULLIF(COUNT(DISTINCT s.PATIENT_ID), 0), 1)   AS "Visits per patient",
    ROUND(SUM(s.BILLED_AMOUNT)
          / NULLIF(COUNT(DISTINCT s.ENCOUNTER_ID), 0))    AS "Billed per visit"
FROM sited s
JOIN claim_condition cc ON s.CLAIM_ID = cc.CLAIM_ID
JOIN SYNTHEA_HEALTHCLAIMS.PUBLIC.CODE_DICTIONARY d ON cc.condition_code = d.CODE
WHERE cc.condition_code IS NOT NULL
GROUP BY s.site_group, d.DESCRIPTION
HAVING COUNT(DISTINCT s.ENCOUNTER_ID) >= 500
ORDER BY s.site_group, "Visits" DESC;
