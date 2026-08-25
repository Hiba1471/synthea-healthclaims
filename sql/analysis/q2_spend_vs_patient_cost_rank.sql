-- =====================================================================
-- Q2: is the "conditions patients pay most for" list just the "biggest
--     spend" list again?
--
-- Largely yes -- the two rankings correlate at Spearman rho 0.971, because
-- what a patient pays is total billed multiplied by their share. But the
-- share is not constant (0% to 78.8%, median 27.3%), and that spread
-- reshuffles the list in a consistent direction:
--
--   cheap, routine, acute illnesses RISE   (patients carry a big share)
--   cancers and serious chronic disease FALL (insurers absorb almost all)
--
-- Sinusitis patients pay 51.7% of the bill; colon cancer patients pay 7.3%.
-- Same inversion found by type of visit, now visible at condition level.
--
-- This comparison previously existed only as a spreadsheet-style derivation
-- outside SQL.
--
-- Results: sql/results/q2_spend_vs_patient_cost_rank_2020_2024.csv
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
        d.DESCRIPTION                AS condition_name,
        SUM(m.billed)                AS billed,
        SUM(m.paid)                  AS paid,
        SUM(m.patient_paid)          AS patient_paid,
        COUNT(DISTINCT m.patient_id) AS patients
    FROM claim_money m
    JOIN claim_condition cc ON m.CLAIM_ID = cc.CLAIM_ID
    JOIN SYNTHEA_HEALTHCLAIMS.PUBLIC.CODE_DICTIONARY d ON cc.condition_code = d.CODE
    WHERE cc.condition_code IS NOT NULL
    GROUP BY d.DESCRIPTION
    HAVING SUM(m.billed) > 0
),
ranked AS (
    SELECT
        b.*,
        ROW_NUMBER() OVER (ORDER BY billed DESC)       AS spend_rank,
        ROW_NUMBER() OVER (ORDER BY patient_paid DESC) AS patient_cost_rank,
        SUM(patient_paid) OVER ()                      AS all_patient_paid
    FROM by_condition b
)
SELECT
    condition_name                                     AS "Condition",
    spend_rank                                         AS "Rank by total spending",
    patient_cost_rank                                  AS "Rank by what patients pay",
    spend_rank - patient_cost_rank                     AS "Places moved (+ = patients pay more than its size suggests)",
    ROUND(100 * patient_paid / NULLIF(paid, 0), 1)     AS "% of the bill patients pay",
    ROUND(billed)                                      AS "Total billed",
    ROUND(patient_paid)                                AS "Paid by patients",
    ROUND(100 * patient_paid / all_patient_paid, 2)    AS "% of everything patients pay",
    patients                                           AS "People affected",
    ROUND(patient_paid / NULLIF(patients, 0))          AS "Paid per person over 5 years",
    CASE
        WHEN spend_rank - patient_cost_rank >=  5 THEN 'Patients carry an unusually large share'
        WHEN spend_rank - patient_cost_rank <= -5 THEN 'Insurers absorb an unusually large share'
        ELSE 'About what its size would suggest'
    END                                                AS "Pattern"
FROM ranked
ORDER BY patient_cost_rank;
