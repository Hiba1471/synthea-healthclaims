-- =====================================================================
-- Retests the three headline findings against condition-level pricing
-- factors supplied in a brief (Synthea prices some procedures at flat,
-- inflated amounts -- see DATA_QUALITY_LOG.md). Billed, paid and
-- patient-paid are all scaled by the same per-condition factor, so a
-- payer-split PERCENTAGE is unchanged and only its DOLLARS move.
--
-- Result: F1 (pregnancy's share of diagnosed spend) drops sharply
-- (39.81% -> 14.76%); F2 (member share of all billed) rises slightly
-- because correction shrinks the low-share bucket, reweighting the
-- blend upward, not because members pay more; F3 (commercial:government
-- ratio) is EXACTLY unchanged, because scaling billed and paid together
-- cancels in a ratio. See sql/results/q1_robustness_three_findings_2020_2024.csv.
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
-- Follow-up: does Finding 2's inverse slope (member-paid share against
-- cost per person, across the 15 care types) survive price correction?
-- Yes, Spearman stays at about -0.6 either way -- but do not quote a
-- second decimal: one tied pair moves the coefficient with the tie
-- convention (RANK() gives -0.571, a naive sort gives -0.586). Ranks
-- first, then CORR on the ranks, since Snowflake's CORR is Pearson.
-- =====================================================================
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
      -- "cholecystitis" contains "cystitis"; tested first so a gallbladder
      -- infection is not claimed by the Kidney & urinary branch below.
      WHEN LOWER(nm) REGEXP '.*cholecystitis.*' THEN 'Infections (other)'
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
