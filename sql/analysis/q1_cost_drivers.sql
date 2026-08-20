-- =====================================================================
-- Q1: WHERE DOES THE MONEY GO?
--
-- North star: top N conditions as a share of condition-attributable spend
--             ($72,685,492,693) and of all spend ($99,111,300,187).
-- Secondary:  cost PER PATIENT by condition -- what it costs to treat one
--             person, not one claim.
--
-- Attribution: CLAIMS.DIAGNOSIS1 when it is a real condition, else
-- DIAGNOSIS2 (the fallback -- DIAGNOSIS1 is ~65% encounter metadata here).
--
-- TWO COLUMNS ADDED AFTER REVIEW, both to stop a specific misreading:
--
--   Median Cost per Patient -- per-patient spend is heavily right-skewed,
--     so the MEAN overstates the typical case. COVID-19 reads $40,749 mean
--     vs $26,649 median. Per section 6 of DATA_ANALYSIS_CONTEXT.md, prefer
--     the median on skewed distributions. Both are reported so the gap is
--     visible.
--
--   Pct Inpatient -- flags conditions whose patient population is
--     SEVERITY-FILTERED. COVID-19 is 99.9% inpatient: only 23,027 of
--     1,259,375 patients (1.8%) carry the diagnosis at all, because Synthea
--     attaches it to hospitalised cases. So "COVID costs $26,649 per
--     patient" is the cost of a COVID HOSPITALISATION, not of COVID. Any
--     condition with a high inpatient share has the same problem and is not
--     comparable to a broad-population condition like gingivitis.
--
-- Results: sql/results/q1_cost_drivers_2020_2024.csv
-- =====================================================================

WITH claim_money AS (
    SELECT
        CLAIM_ID,
        MIN(PATIENT_ID)      AS patient_id,
        SUM(BILLED_AMOUNT)   AS billed,
        SUM(PAID_BY_PATIENT) AS patient_paid,
        SUM(PAID_AMOUNT)     AS paid,
        -- share of this claim's spend that happened in an inpatient setting
        SUM(IFF(ENCOUNTERCLASS = 'inpatient', BILLED_AMOUNT, 0)) AS inpatient_billed
    FROM SYNTHEA_HEALTHCLAIMS.PUBLIC.V_CLAIMS_TX_CLEAN
    WHERE NOT IS_ADMIN_NOISE_CODE
      AND PROCEDURECODE IS NOT NULL
    GROUP BY CLAIM_ID
),
claim_condition AS (
    SELECT
        c.CLAIM_ID,
        CASE WHEN d1.IS_CONDITION THEN c.DIAGNOSIS1
             WHEN d2.IS_CONDITION THEN c.DIAGNOSIS2
        END AS condition_code
    FROM SYNTHETIC_HEALTHCARE_DATA_CLINICAL_AND_CLAIMS.SILVER.CLAIMS c
    LEFT JOIN SYNTHEA_HEALTHCLAIMS.PUBLIC.CODE_DICTIONARY d1 ON c.DIAGNOSIS1 = d1.CODE
    LEFT JOIN SYNTHEA_HEALTHCLAIMS.PUBLIC.CODE_DICTIONARY d2 ON c.DIAGNOSIS2 = d2.CODE
),
-- per-patient totals first, so a MEDIAN across patients is possible
patient_totals AS (
    SELECT
        cc.condition_code,
        m.patient_id,
        SUM(m.billed) AS patient_billed
    FROM claim_money m
    JOIN claim_condition cc ON m.CLAIM_ID = cc.CLAIM_ID
    WHERE cc.condition_code IS NOT NULL
    GROUP BY cc.condition_code, m.patient_id
),
median_by_condition AS (
    SELECT condition_code, MEDIAN(patient_billed) AS median_cost_per_patient
    FROM patient_totals
    GROUP BY condition_code
),
by_condition AS (
    SELECT
        d.CODE                             AS condition_code,
        d.DESCRIPTION                      AS condition_name,
        SUM(m.billed)                      AS total_billed,
        COUNT(*)                           AS claims,
        COUNT(DISTINCT m.patient_id)       AS patients,
        SUM(m.patient_paid)                AS patient_paid,
        SUM(m.paid)                        AS total_paid,
        SUM(m.inpatient_billed)            AS inpatient_billed
    FROM claim_money m
    JOIN claim_condition cc ON m.CLAIM_ID = cc.CLAIM_ID
    JOIN SYNTHEA_HEALTHCLAIMS.PUBLIC.CODE_DICTIONARY d ON cc.condition_code = d.CODE
    WHERE cc.condition_code IS NOT NULL
    GROUP BY d.CODE, d.DESCRIPTION
    HAVING SUM(m.billed) > 0
),
ranked AS (
    SELECT
        b.*,
        mb.median_cost_per_patient,
        ROW_NUMBER() OVER (ORDER BY b.total_billed DESC)        AS rank,
        SUM(b.total_billed) OVER ()                             AS attributable_total,
        SUM(b.total_billed) OVER (ORDER BY b.total_billed DESC
                                  ROWS BETWEEN UNBOUNDED PRECEDING
                                           AND CURRENT ROW)     AS cumulative_billed
    FROM by_condition b
    LEFT JOIN median_by_condition mb ON b.condition_code = mb.condition_code
)
SELECT
    rank                                                        AS "Rank",
    condition_code                                              AS "Condition Code",
    condition_name                                              AS "Condition",
    total_billed                                                AS "Total Billed",
    ROUND(100 * total_billed / attributable_total, 2)           AS "% of Attributable",
    ROUND(100 * cumulative_billed / attributable_total, 2)      AS "Cumulative % of Attributable",
    -- 99,111,300,187 = all in-window spend, incl. the 26.7% with no diagnosis
    ROUND(100 * total_billed / 99111300187, 2)                  AS "% of All Spend",
    ROUND(100 * cumulative_billed / 99111300187, 2)             AS "Cumulative % of All Spend",
    patients                                                    AS "Patients",
    claims                                                      AS "Claims",
    ROUND(total_billed / NULLIF(patients, 0), 2)                AS "Cost per Patient",
    ROUND(median_cost_per_patient, 2)                           AS "Median Cost per Patient",
    ROUND(total_billed / NULLIF(claims, 0), 2)                  AS "Cost per Claim",
    ROUND(claims / NULLIF(patients, 0), 1)                      AS "Claims per Patient",
    ROUND(100 * inpatient_billed / NULLIF(total_billed, 0), 1)  AS "% Inpatient",
    ROUND(100 * patient_paid / NULLIF(total_paid, 0), 1)        AS "% Borne by Patient"
FROM ranked
ORDER BY rank;
