-- =====================================================================
-- Q3 follow-up: q3_care_type_mix_by_site_group.sql shows VA-named sites
-- lean 64.9% Kidney & urinary with 6.31 repeat visits per condition
-- against 3.42 elsewhere -- too coarse to say why, since that care type
-- mixes dialysis with bladder infections. Drops to the specific
-- condition to rule in or out a third possibility: that the visit count
-- is neither good access nor unresolved care, but simply dialysis being
-- three sessions a week for life. Hospice/nursing sites run the same
-- test for their mirror puzzle (1.0-2.7 visits at up to $16,030 each).
--
-- Both groups matched on NAME; nothing in the data marks a facility as
-- either.
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
