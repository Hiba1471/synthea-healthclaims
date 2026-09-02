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

-- =====================================================================
-- FOLLOW-UP: does Finding 2's inverse slope (member-paid share against
-- cost per person, across the 15 care types) survive price correction?
--
-- Yes. Spearman stays at about -0.6 either way.
--
-- DO NOT QUOTE A SECOND DECIMAL. The corrected data contains one tied
-- pair (Respiratory & ENT and Injury & trauma both land on 25.0%), and
-- the coefficient moves with the tie convention: Snowflake RANK() gives
-- -0.571, a naive sort-index in Python gives -0.586, and a proper
-- tie-averaged Spearman would give a third value. The as-billed figure is
-- -0.600 under both. Only "about -0.6, essentially unchanged" is robust to
-- the choice, and that is all the report claims.
--
-- The illustration that does NOT survive, and why it was pulled from the
-- report's Finding 2 paragraph: allergy & immune reads 10.0% share on
-- $175,111 per person as billed, a textbook expensive-care-low-share
-- case. It carries the largest documented pricing gap in this dataset
-- (~89x), and corrected it becomes 15.0% on $2,432 -- cheap care at a
-- middling share, illustrating the opposite of the point it was used for.
-- Cancer holds its shape (8.3% on $104,622 -> 7.4% on $41,007) and is
-- used instead.
-- =====================================================================
-- Spearman rank correlation between member-paid share and cost per person,
-- across the 15 care types, computed twice: as billed and price-corrected.
-- Ranks first, then CORR on the ranks (Snowflake's CORR is Pearson).
WITH claim_raw AS (
    SELECT CLAIM_ID, MIN(PATIENT_ID) AS patient_id,
           SUM(BILLED_AMOUNT) AS billed, SUM(PAID_AMOUNT) AS paid,
           SUM(PAID_BY_PATIENT) AS patient_paid
    FROM SYNTHEA_HEALTHCLAIMS.PUBLIC.V_CLAIMS_TX_CLEAN
    WHERE NOT IS_ADMIN_NOISE_CODE AND PROCEDURECODE IS NOT NULL
    GROUP BY CLAIM_ID
),
cc AS (
    SELECT c.CLAIM_ID,
           CASE WHEN d1.IS_CONDITION THEN c.DIAGNOSIS1 WHEN d2.IS_CONDITION THEN c.DIAGNOSIS2 END AS code
    FROM SYNTHETIC_HEALTHCARE_DATA_CLINICAL_AND_CLAIMS.SILVER.CLAIMS c
    LEFT JOIN SYNTHEA_HEALTHCLAIMS.PUBLIC.CODE_DICTIONARY d1 ON c.DIAGNOSIS1 = d1.CODE
    LEFT JOIN SYNTHEA_HEALTHCLAIMS.PUBLIC.CODE_DICTIONARY d2 ON c.DIAGNOSIS2 = d2.CODE
),
j AS (
    SELECT r.patient_id, r.billed, r.paid, r.patient_paid, d.DESCRIPTION AS nm,
      CASE cc.code
        WHEN '72892002' THEN 0.116 WHEN '66383009' THEN 0.067 WHEN '424132000' THEN 0.091
        WHEN '109570002' THEN 0.059 WHEN '68496003' THEN 0.050 WHEN '419199007' THEN 0.011
        WHEN '18718003' THEN 0.133 WHEN '312608009' THEN 0.189 WHEN '10509002' THEN 0.108
        WHEN '230690007' THEN 0.261 WHEN '307426000' THEN 0.042 ELSE 1.0 END AS f
    FROM claim_raw r JOIN cc ON r.CLAIM_ID = cc.CLAIM_ID
    JOIN SYNTHEA_HEALTHCLAIMS.PUBLIC.CODE_DICTIONARY d ON cc.code = d.CODE
    WHERE cc.code IS NOT NULL
),
typed AS (
    SELECT CASE
      WHEN LOWER(nm) REGEXP '.*(gingiv|dental|tooth|teeth|molar|jaw|palatinus|temporomandibular|mandible|alveolitis).*' THEN 'Dental & oral'
      WHEN LOWER(nm) REGEXP '.*(pregnan|miscarriage|ovum|tubal|newborn|antenatal|postnatal).*' THEN 'Maternity'
      WHEN LOWER(nm) REGEXP '.*(malignant|carcinoma|neoplasm|polyp of colon).*' THEN 'Cancer & tumours'
      WHEN LOWER(nm) REGEXP '.*(kidney|renal|cystitis|pyelonephritis|urinary|bladder).*' THEN 'Kidney & urinary'
      WHEN LOWER(nm) REGEXP '.*(heart|stroke|myocardial|atrial|aortic|coronary|hypertension|cardiac|circulat).*' THEN 'Heart & circulation'
      WHEN LOWER(nm) REGEXP '.*(bronchitis|covid|pharyngitis|sinusitis|sore throat|emphysema|asthma|otitis|respiratory|pneumon|influenza).*' THEN 'Respiratory & ENT'
      WHEN LOWER(nm) REGEXP '.*(diabet|obesity|lipid|glycemia|metabolic|triglyceride|osteoporosis|body mass).*' THEN 'Diabetes & metabolic'
      WHEN LOWER(nm) REGEXP '.*(drug|alcohol|anxiety|attention deficit|sleep|suicide|overdose|depress|stress).*' THEN 'Mental health & substance use'
      WHEN LOWER(nm) REGEXP '.*(injury|fracture|sprain|laceration|burn|concussion|rupture|dislocation|wound).*' THEN 'Injury & trauma'
      WHEN LOWER(nm) REGEXP '.*allerg.*' THEN 'Allergy & immune'
      WHEN LOWER(nm) REGEXP '.*(seizure|alzheimer|neuropathy|epilep|dementia).*' THEN 'Brain & nervous system'
      WHEN LOWER(nm) REGEXP '.*(sepsis|immunodeficiency|appendicitis|cholecystitis|infection|infective|viral|bacterial).*' THEN 'Infections (other)'
      WHEN LOWER(nm) REGEXP '.*(anemia|anaemia).*' THEN 'Blood disorders'
      WHEN LOWER(nm) REGEXP '.*pain.*' THEN 'Chronic pain'
      ELSE 'Other' END AS care_type,
      patient_id, billed, paid, patient_paid, f
    FROM j
),
agg AS (
    SELECT care_type,
      100.0*SUM(patient_paid)/NULLIF(SUM(paid),0)         AS share_orig,
      SUM(billed)/NULLIF(COUNT(DISTINCT patient_id),0)    AS cpp_orig,
      100.0*SUM(patient_paid*f)/NULLIF(SUM(paid*f),0)     AS share_adj,
      SUM(billed*f)/NULLIF(COUNT(DISTINCT patient_id),0)  AS cpp_adj
    FROM typed GROUP BY care_type
),
ranked AS (
    SELECT RANK() OVER (ORDER BY share_orig) rso, RANK() OVER (ORDER BY cpp_orig) rco,
           RANK() OVER (ORDER BY share_adj) rsa, RANK() OVER (ORDER BY cpp_adj) rca
    FROM agg
)
SELECT ROUND(CORR(rso, rco), 3) AS spearman_as_billed,
       ROUND(CORR(rsa, rca), 3) AS spearman_corrected
FROM ranked;
