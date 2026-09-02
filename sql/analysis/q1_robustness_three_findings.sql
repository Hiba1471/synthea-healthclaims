-- =====================================================================
-- ROBUSTNESS TEST of three findings against condition-level price
-- adjustment factors supplied in a brief, run 2026-09-01.
--
-- FACTORS ARE MULTIPLIERS, not divisors. Five came from the brief
-- (pregnancy 0.116, gingivitis 0.067, NSCLC 0.091, dental caries 0.059,
-- polyp 0.050); six more from this repo's own audit, which the brief did
-- not state (allergy 0.011, gingival disease 0.133, laceration 0.189,
-- bronchitis 0.108, stroke 0.261, UTI 0.042). Kidney disease, breast
-- cancer and COVID stay at 1.0 as the brief specified, matching this
-- repo's finding that all three are NOT inflated.
--
-- ONE FACTOR CONFLICTS AND THE BRIEF'S VALUE WAS USED. Gingivitis: the
-- brief says 0.067, this repo's audit produced 0.080 (a 16% difference).
-- Both sit inside the $500-1,200 scaling-and-root-planing benchmark --
-- the brief implies a ~$715 midpoint, the repo used $850. Neither is
-- wrong; the brief's value is used here because the brief owns the audit.
--
-- METHOD: billed, paid and patient-paid are all multiplied by the same
-- per-condition factor, so a single condition's payer-split PERCENTAGE is
-- unchanged and only its DOLLARS move. Rationale in
-- q2_care_type_breakdown_repriced.sql -- the documented defect is that
-- Synthea prices procedures at flat arbitrary amounts, not that its
-- copay/coinsurance mechanism is broken.
--
-- RESULTS:
--   F1 pregnancy share of diagnosed spend  39.81% -> 14.76%
--                                          $28.93B -> $3.36B
--   F2 member share of all billed          20.44% -> 23.25%  (share UP,
--                                          dollars DOWN $20.26B -> $11.43B)
--   F3 commercial:government ratio         UNCHANGED for every condition
--
-- WHY F2's SHARE RISES WHILE ITS DOLLARS FALL, verified separately: the 11
-- adjusted conditions carry $54.89B at a 17.73% member share; everything
-- else carries $44.22B at 23.80%. Shrinking the low-member-share bucket by
-- ~90% leaves the mix dominated by the high-member-share one, so the
-- blended figure rises to 23.25%, just under the 23.80% of the untouched
-- remainder. This is reweighting, not members paying more.
--
-- WHY F3 IS EXACTLY UNCHANGED: scaling billed and paid by the same factor
-- inside one condition cancels in the ratio. Confirmed empirically, not
-- just algebraically -- pregnancy 25.2x -> 25.2x, gingivitis 17.1x ->
-- 17.1x, allergy 9.4x -> 9.4x. Finding 3 is immune to this whole class of
-- pricing defect, which makes it the most robust of the three.
--
-- Results: sql/results/q1_robustness_three_findings_2020_2024.csv
-- =====================================================================
WITH claim_money AS (
    SELECT CLAIM_ID,
           MIN(PATIENT_ID)      AS patient_id,
           MIN(PAYER_TYPE)      AS payer_type,
           SUM(BILLED_AMOUNT)   AS billed,
           SUM(PAID_AMOUNT)     AS paid,
           SUM(PAID_BY_PATIENT) AS patient_paid
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
-- factors as MULTIPLIERS, exactly as stated in the brief where stated
adj AS (
    SELECT m.CLAIM_ID, m.patient_id, m.payer_type, cc.condition_code,
           m.billed, m.paid, m.patient_paid,
           CASE cc.condition_code
               WHEN '72892002'  THEN 0.116   -- pregnancy      (brief)
               WHEN '66383009'  THEN 0.067   -- gingivitis     (brief)
               WHEN '424132000' THEN 0.091   -- NSCLC stage 1  (brief)
               WHEN '109570002' THEN 0.059   -- dental caries  (brief)
               WHEN '68496003'  THEN 0.050   -- polyp of colon (brief)
               WHEN '419199007' THEN 0.011   -- allergy        (repo audit)
               WHEN '18718003'  THEN 0.133   -- gingival dis.  (repo audit)
               WHEN '312608009' THEN 0.189   -- laceration     (repo audit)
               WHEN '10509002'  THEN 0.108   -- bronchitis     (repo audit)
               WHEN '230690007' THEN 0.261   -- stroke         (repo audit)
               WHEN '307426000' THEN 0.042   -- UTI            (repo audit)
               ELSE 1.0                       -- incl. kidney, breast ca, COVID
           END AS f
    FROM claim_money m
    LEFT JOIN claim_condition cc ON m.CLAIM_ID = cc.CLAIM_ID
),
diag AS (SELECT * FROM adj WHERE condition_code IS NOT NULL)

SELECT 'F1 pregnancy share of diagnosed'      AS metric,
       ROUND(100.0 * SUM(IFF(condition_code='72892002', billed, 0))
             / SUM(billed), 2)                AS original_pct,
       ROUND(100.0 * SUM(IFF(condition_code='72892002', billed*f, 0))
             / SUM(billed*f), 2)              AS adjusted_pct,
       ROUND(SUM(IFF(condition_code='72892002', billed, 0)))   AS original_dollars,
       ROUND(SUM(IFF(condition_code='72892002', billed*f, 0))) AS adjusted_dollars
FROM diag
UNION ALL
SELECT 'F2 member share of ALL billed',
       ROUND(100.0 * SUM(patient_paid) / SUM(billed), 2),
       ROUND(100.0 * SUM(patient_paid*f) / SUM(billed*f), 2),
       ROUND(SUM(patient_paid)),
       ROUND(SUM(patient_paid*f))
FROM adj;
