-- =====================================================================
-- Q2 EXTENSION: the median member-paid total, beside the mean of $16,084.
--
-- WHY THIS EXISTS. q2_who_pays.sql reports patient-paid-per-patient of
-- $16,084 as an AVERAGE (total patient-paid / patient count). Per section 6
-- of DATA_ANALYSIS_CONTEXT.md, an average on a right-skewed distribution
-- overstates the typical case -- this project's own rule, applied everywhere
-- else (cost per claim, cost per patient by condition), had not yet been
-- applied to this specific headline figure. This computes the median and P75
-- /P90 of five-year member-paid total ACROSS ALL 1,259,375 MEMBERS (including
-- the ones with $0 in patient-paid spend, since "$16,084 per member" as
-- worded implies every member, not just those with a claim).
--
-- Results: sql/results/q2_member_paid_percentiles_2020_2024.csv
-- =====================================================================

WITH claim_money AS (
    -- claim-level, not patient-level: a patient with $0 patient-paid across
    -- every claim still appears here as long as they have >=1 claim, which is
    -- what "1,259,375 members" means throughout this report -- it is the
    -- population with activity in the windowed claims view, not Synthea's
    -- full generated patient roster (SILVER.PATIENTS), which is larger and
    -- includes people with no billed activity in 2020-2024 at all.
    SELECT CLAIM_ID, MIN(PATIENT_ID) AS patient_id, SUM(PAID_BY_PATIENT) AS patient_paid
    FROM SYNTHEA_HEALTHCLAIMS.PUBLIC.V_CLAIMS_TX_CLEAN
    WHERE NOT IS_ADMIN_NOISE_CODE AND PROCEDURECODE IS NOT NULL
    GROUP BY CLAIM_ID
),
per_member AS (
    SELECT patient_id, SUM(patient_paid) AS paid
    FROM claim_money
    GROUP BY patient_id
)
SELECT
    COUNT(*)                                                      AS "All members",
    ROUND(AVG(paid))                                              AS "Mean (the $16,084 figure)",
    ROUND(MEDIAN(paid))                                           AS "Median",
    ROUND(PERCENTILE_CONT(0.75) WITHIN GROUP (ORDER BY paid))     AS "P75",
    ROUND(PERCENTILE_CONT(0.90) WITHIN GROUP (ORDER BY paid))     AS "P90",
    ROUND(100.0 * SUM(IFF(paid=0,1,0)) / COUNT(*), 2)             AS "% of members with $0 patient-paid"
FROM per_member;
