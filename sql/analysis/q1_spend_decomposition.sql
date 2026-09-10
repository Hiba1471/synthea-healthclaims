-- =====================================================================
-- Q1: why do a few conditions dominate spend? Decomposes spend into
-- patients x claims per patient x cost per claim, each expressed as a
-- multiple of the MEDIAN condition so the three are comparable and the
-- dominant driver is named. The top 20 conditions get there by being
-- moderately extreme on all three at once, not extreme on any one.
-- =====================================================================

WITH claim_money AS (
    SELECT
        CLAIM_ID,
        MIN(PATIENT_ID)      AS patient_id,
        SUM(BILLED_AMOUNT)   AS billed,
        SUM(PAID_AMOUNT)     AS paid,
        SUM(PAID_BY_PATIENT) AS patient_paid
    FROM SYNTHEA_HEALTHCLAIMS.PUBLIC.V_CLAIMS_TX_CLEAN
    WHERE NOT IS_ADMIN_NOISE_CODE
      AND PROCEDURECODE IS NOT NULL
    GROUP BY CLAIM_ID
),
claim_condition AS (
    SELECT
        c.CLAIM_ID,
        CASE WHEN d1.IS_CONDITION THEN c.DIAGNOSIS1
             WHEN d2.IS_CONDITION THEN c.DIAGNOSIS2 END AS condition_code
    FROM SYNTHETIC_HEALTHCARE_DATA_CLINICAL_AND_CLAIMS.SILVER.CLAIMS c
    LEFT JOIN SYNTHEA_HEALTHCLAIMS.PUBLIC.CODE_DICTIONARY d1 ON c.DIAGNOSIS1 = d1.CODE
    LEFT JOIN SYNTHEA_HEALTHCLAIMS.PUBLIC.CODE_DICTIONARY d2 ON c.DIAGNOSIS2 = d2.CODE
),
by_condition AS (
    SELECT
        d.CODE                        AS condition_code,
        d.DESCRIPTION                 AS condition_name,
        SUM(m.billed)                 AS billed,
        COUNT(*)                      AS claims,
        COUNT(DISTINCT m.patient_id)  AS patients,
        SUM(m.patient_paid)           AS patient_paid,
        SUM(m.paid)                   AS paid
    FROM claim_money m
    JOIN claim_condition cc ON m.CLAIM_ID = cc.CLAIM_ID
    JOIN SYNTHEA_HEALTHCLAIMS.PUBLIC.CODE_DICTIONARY d ON cc.condition_code = d.CODE
    WHERE cc.condition_code IS NOT NULL
    GROUP BY d.CODE, d.DESCRIPTION
    HAVING SUM(m.billed) > 0
),
-- the three drivers, plus the median condition on each
drivers AS (
    SELECT
        b.*,
        b.claims / NULLIF(b.patients, 0)                       AS claims_per_patient,
        b.billed / NULLIF(b.claims, 0)                         AS cost_per_claim,
        MEDIAN(b.patients)                     OVER ()         AS med_patients,
        MEDIAN(b.claims / NULLIF(b.patients,0)) OVER ()        AS med_claims_per_patient,
        MEDIAN(b.billed / NULLIF(b.claims,0))   OVER ()        AS med_cost_per_claim,
        SUM(b.billed)                          OVER ()         AS all_billed,
        SUM(b.claims)                          OVER ()         AS all_claims,
        ROW_NUMBER() OVER (ORDER BY b.billed DESC)             AS spend_rank
    FROM by_condition b
),
scored AS (
    SELECT
        d.*,
        patients            / NULLIF(med_patients, 0)           AS reach_multiple,
        claims_per_patient  / NULLIF(med_claims_per_patient, 0) AS frequency_multiple,
        cost_per_claim      / NULLIF(med_cost_per_claim, 0)     AS price_multiple
    FROM drivers d
)
SELECT
    spend_rank                                        AS "Rank by total spend",
    condition_code                                    AS "Condition code",
    condition_name                                    AS "Condition",
    ROUND(billed)                                     AS "Total billed",
    ROUND(100 * billed / all_billed, 3)               AS "% of all spending",
    claims                                            AS "Number of claims",
    ROUND(100 * claims / all_claims, 3)               AS "% of all claims",
    -- positive = costs more per claim than average; negative = cheap and high volume
    ROUND(100 * billed / all_billed
          - 100 * claims / all_claims, 2)             AS "Spend share minus claim share",
    patients                                          AS "People affected",
    ROUND(claims_per_patient, 2)                      AS "Claims per person",
    ROUND(cost_per_claim, 2)                          AS "Cost per claim",
    ROUND(billed / NULLIF(patients, 0), 2)            AS "Cost per person",

    -- each driver as a multiple of the median condition
    ROUND(reach_multiple, 2)                          AS "How many more people than a typical condition",
    ROUND(frequency_multiple, 2)                      AS "How many more visits each than typical",
    ROUND(price_multiple, 2)                          AS "How much dearer per claim than typical",

    CASE
        WHEN GREATEST(reach_multiple, frequency_multiple, price_multiple) < 2
            THEN 'Balanced'
        WHEN reach_multiple >= GREATEST(frequency_multiple, price_multiple)
            THEN 'Reach - affects many people'
        WHEN frequency_multiple >= price_multiple
            THEN 'Frequency - many visits each'
        ELSE 'Price - expensive per claim'
    END                                               AS "What drives its cost",
    ROUND(GREATEST(reach_multiple, frequency_multiple, price_multiple), 1)
                                                      AS "Size of that driver",
    ROUND(100 * patient_paid / NULLIF(paid, 0), 1)    AS "% of the bill patients pay"
FROM scored
ORDER BY spend_rank;
