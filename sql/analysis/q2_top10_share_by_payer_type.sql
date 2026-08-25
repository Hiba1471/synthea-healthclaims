-- =====================================================================
-- Q2: for the ten conditions where patients carry the biggest share of the
--     bill, how does that share differ by kind of insurance?
--
-- Same ten conditions as q2_top10_by_share_of_bill.sql, but pivoted so the
-- three kinds of insurance sit side by side. This is where the interaction
-- shows: the overall share for a condition is a blend, and commercial and
-- government patients experience the same illness very differently.
--
-- Uninsured patients are shown for completeness but always pay 100% by
-- definition, so the meaningful comparison is commercial vs government.
--
-- Floor of 5,000 people affected, so a condition with a handful of patients
-- cannot top a ranking computed from almost nothing.
--
-- Results: sql/results/q2_top10_share_by_payer_type_2020_2024.csv
-- =====================================================================
WITH claim_money AS (
    SELECT CLAIM_ID, MIN(PATIENT_ID) AS patient_id, MIN(PAYER_TYPE) AS payer_type,
           SUM(PAID_AMOUNT) AS paid, SUM(PAID_BY_PATIENT) AS patient_paid,
           SUM(PAID_BY_PAYER) AS insurer_paid
    FROM SYNTHEA_HEALTHCLAIMS.PUBLIC.V_CLAIMS_TX_CLEAN
    WHERE NOT IS_ADMIN_NOISE_CODE AND PROCEDURECODE IS NOT NULL
    GROUP BY CLAIM_ID
),
claim_condition AS (
    SELECT c.CLAIM_ID,
           CASE WHEN d1.IS_CONDITION THEN c.DIAGNOSIS1
                WHEN d2.IS_CONDITION THEN c.DIAGNOSIS2 END AS condition_code
    FROM SYNTHETIC_HEALTHCARE_DATA_CLINICAL_AND_CLAIMS.SILVER.CLAIMS c
    LEFT JOIN SYNTHEA_HEALTHCLAIMS.PUBLIC.CODE_DICTIONARY d1 ON c.DIAGNOSIS1 = d1.CODE
    LEFT JOIN SYNTHEA_HEALTHCLAIMS.PUBLIC.CODE_DICTIONARY d2 ON c.DIAGNOSIS2 = d2.CODE
),
scoped AS (
    SELECT d.DESCRIPTION AS condition_name, m.*
    FROM claim_money m
    JOIN claim_condition cc ON m.CLAIM_ID = cc.CLAIM_ID
    JOIN SYNTHEA_HEALTHCLAIMS.PUBLIC.CODE_DICTIONARY d ON cc.condition_code = d.CODE
    WHERE cc.condition_code IS NOT NULL
),
overall AS (
    SELECT condition_name,
           SUM(patient_paid)/NULLIF(SUM(paid),0) AS share_all,
           SUM(patient_paid) AS patient_paid_all,
           COUNT(DISTINCT patient_id) AS patients_all
    FROM scoped GROUP BY condition_name
    HAVING SUM(paid) > 0 AND COUNT(DISTINCT patient_id) >= 5000
    QUALIFY ROW_NUMBER() OVER (ORDER BY SUM(patient_paid)/NULLIF(SUM(paid),0) DESC) <= 10
)
SELECT
    ROW_NUMBER() OVER (ORDER BY o.share_all DESC)          AS "Rank",
    o.condition_name                                       AS "Condition",
    ROUND(100 * o.share_all, 1)                            AS "% patients pay (everyone)",
    ROUND(100 * SUM(IFF(s.payer_type='Commercial', s.patient_paid, 0))
          / NULLIF(SUM(IFF(s.payer_type='Commercial', s.paid, 0)), 0), 1)
                                                           AS "% patients pay - Commercial",
    ROUND(100 * SUM(IFF(s.payer_type='Government', s.patient_paid, 0))
          / NULLIF(SUM(IFF(s.payer_type='Government', s.paid, 0)), 0), 1)
                                                           AS "% patients pay - Government",
    ROUND(100 * SUM(IFF(s.payer_type='Self-Pay / Uninsured', s.patient_paid, 0))
          / NULLIF(SUM(IFF(s.payer_type='Self-Pay / Uninsured', s.paid, 0)), 0), 1)
                                                           AS "% patients pay - Uninsured",
    ROUND(100 * SUM(IFF(s.payer_type='Commercial', s.patient_paid, 0))
          / NULLIF(SUM(IFF(s.payer_type='Commercial', s.paid, 0)), 0)
        - 100 * SUM(IFF(s.payer_type='Government', s.patient_paid, 0))
          / NULLIF(SUM(IFF(s.payer_type='Government', s.paid, 0)), 0), 1)
                                                           AS "Commercial worse by (points)",
    ROUND(SUM(IFF(s.payer_type='Commercial', s.insurer_paid, 0)))
                                                           AS "Insurer paid - Commercial",
    ROUND(SUM(IFF(s.payer_type='Government', s.insurer_paid, 0)))
                                                           AS "Insurer paid - Government",
    ROUND(o.patient_paid_all)                              AS "Paid by patients over 5 years",
    o.patients_all                                         AS "People affected"
FROM scoped s
JOIN overall o ON s.condition_name = o.condition_name
GROUP BY o.condition_name, o.share_all, o.patient_paid_all, o.patients_all
ORDER BY "Rank";
