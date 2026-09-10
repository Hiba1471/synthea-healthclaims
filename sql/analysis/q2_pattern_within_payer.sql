-- =====================================================================
-- Q2 follow-up: does the cheap-care/high-share pattern (Spearman -0.60
-- across all 15 care types) survive within a single payer type, or is it
-- partly payer mix (government patients pay near-zero, and low-share
-- care types skew government-heavy)? Splits commercial from government;
-- uninsured excluded since they pay 100% by definition.
--
-- Result: the pattern sharpens, it does not collapse -- -0.72 within
-- commercial, -0.88 within government, both stronger than the -0.60
-- blend. Payer mix was damping the relationship, not manufacturing it.
-- Brain & nervous system, an apparent counter-example blended (cheap at
-- 8.5% share), is 90.2% government-funded and reads 40.2% commercial
-- once split -- not an exception, just a mix effect. The government
-- -0.88 is arithmetic (a flat copay against a growing bill), not
-- evidence of behaviour, and should not be cited as such. The care-type
-- ladder is copied from q2_patient_cost_by_care_type.sql -- edit there
-- first (see tools/check_care_type_ladder.py).
-- =====================================================================

WITH claim_money AS (
    SELECT CLAIM_ID,
           MIN(PATIENT_ID)      AS patient_id,
           MIN(PAYER_TYPE)      AS payer_type,
           SUM(PAID_AMOUNT)     AS paid,
           SUM(PAID_BY_PATIENT) AS patient_paid
    FROM SYNTHEA_HEALTHCLAIMS.PUBLIC.V_CLAIMS_TX_CLEAN
    WHERE NOT IS_ADMIN_NOISE_CODE AND PROCEDURECODE IS NOT NULL
    GROUP BY CLAIM_ID
    HAVING SUM(PAID_AMOUNT) > 0
),
claim_condition AS (
    SELECT c.CLAIM_ID,
           CASE WHEN d1.IS_CONDITION THEN c.DIAGNOSIS1
                WHEN d2.IS_CONDITION THEN c.DIAGNOSIS2 END AS condition_code
    FROM SYNTHETIC_HEALTHCARE_DATA_CLINICAL_AND_CLAIMS.SILVER.CLAIMS c
    LEFT JOIN SYNTHEA_HEALTHCLAIMS.PUBLIC.CODE_DICTIONARY d1 ON c.DIAGNOSIS1 = d1.CODE
    LEFT JOIN SYNTHEA_HEALTHCLAIMS.PUBLIC.CODE_DICTIONARY d2 ON c.DIAGNOSIS2 = d2.CODE
),
classified AS (
    SELECT m.patient_id, m.payer_type, m.paid, m.patient_paid,
        CASE
            WHEN LOWER(d.DESCRIPTION) REGEXP '.*(gingiv|dental|tooth|teeth|molar|jaw|palatinus|temporomandibular|mandible|alveolitis).*'
                THEN 'Dental & oral'
            WHEN LOWER(d.DESCRIPTION) REGEXP '.*(pregnan|miscarriage|ovum|tubal|newborn|antenatal|postnatal).*'
                THEN 'Maternity'
            WHEN LOWER(d.DESCRIPTION) REGEXP '.*(malignant|carcinoma|neoplasm|polyp of colon).*'
                THEN 'Cancer & tumours'
            -- "cholecystitis" contains the substring "cystitis", so the Kidney &
            -- urinary branch below would otherwise claim a gallbladder infection.
            -- Tested first and routed where it belongs.
            WHEN LOWER(d.DESCRIPTION) REGEXP '.*cholecystitis.*'
                THEN 'Infections (other)'
            WHEN LOWER(d.DESCRIPTION) REGEXP '.*(kidney|renal|cystitis|pyelonephritis|urinary|bladder).*'
                THEN 'Kidney & urinary'
            WHEN LOWER(d.DESCRIPTION) REGEXP '.*(heart|stroke|myocardial|atrial|aortic|coronary|hypertension|cardiac|circulat).*'
                THEN 'Heart & circulation'
            WHEN LOWER(d.DESCRIPTION) REGEXP '.*(bronchitis|covid|pharyngitis|sinusitis|sore throat|emphysema|asthma|otitis|respiratory|pneumon|influenza).*'
                THEN 'Respiratory & ENT'
            WHEN LOWER(d.DESCRIPTION) REGEXP '.*(diabet|obesity|lipid|glycemia|metabolic|triglyceride|osteoporosis|body mass).*'
                THEN 'Diabetes & metabolic'
            WHEN LOWER(d.DESCRIPTION) REGEXP '.*(drug|alcohol|anxiety|attention deficit|sleep|suicide|overdose|depress|stress).*'
                THEN 'Mental health & substance use'
            WHEN LOWER(d.DESCRIPTION) REGEXP '.*(injury|fracture|sprain|laceration|burn|concussion|rupture|dislocation|wound).*'
                THEN 'Injury & trauma'
            WHEN LOWER(d.DESCRIPTION) REGEXP '.*allerg.*'
                THEN 'Allergy & immune'
            WHEN LOWER(d.DESCRIPTION) REGEXP '.*(seizure|alzheimer|neuropathy|epilep|dementia).*'
                THEN 'Brain & nervous system'
            WHEN LOWER(d.DESCRIPTION) REGEXP '.*(sepsis|immunodeficiency|appendicitis|cholecystitis|infection|infective|viral|bacterial).*'
                THEN 'Infections (other)'
            WHEN LOWER(d.DESCRIPTION) REGEXP '.*(anemia|anaemia).*'
                THEN 'Blood disorders'
            WHEN LOWER(d.DESCRIPTION) REGEXP '.*pain.*'
                THEN 'Chronic pain'
            ELSE 'Other'
        END AS care_type
    FROM claim_money m
    JOIN claim_condition cc ON m.CLAIM_ID = cc.CLAIM_ID
    JOIN SYNTHEA_HEALTHCLAIMS.PUBLIC.CODE_DICTIONARY d ON cc.condition_code = d.CODE
    WHERE cc.condition_code IS NOT NULL
      AND m.payer_type IN ('Commercial', 'Government')
)
SELECT
    payer_type                                            AS "Insurance type",
    care_type                                             AS "Type of care",
    COUNT(*)                                              AS "Claims",
    ROUND(SUM(paid))                                      AS "Total paid",
    ROUND(100 * SUM(patient_paid) / SUM(paid), 1)         AS "Patient share",
    ROUND(SUM(paid) / COUNT(DISTINCT patient_id))         AS "Paid per person",
    ROUND(MEDIAN(paid))                                   AS "Median claim",
    ROUND(AVG(paid))                                      AS "Average claim",
    ROUND(100 * AVG(IFF(patient_paid = 0, 1, 0)), 1)      AS "% of claims patient pays nothing"
FROM classified
GROUP BY payer_type, care_type
HAVING COUNT(*) >= 1000
ORDER BY payer_type, "Paid per person";
