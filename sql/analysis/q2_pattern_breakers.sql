-- =====================================================================
-- Q2 follow-up: two care types break the cheap-care/high-share rule
-- (patients carry more of cheaper care, since it stays under the annual
-- out-of-pocket max) -- Infections at $24,713/person but 28.0% patient
-- share, Brain & nervous at $8,939/person but only 8.5%. Two candidate
-- explanations, tested together: PAYER MIX (a care type weighted toward
-- near-zero-paying government patients reads low regardless of price --
-- emits spend split by payer type) and CLAIM SIZE (the cap acts on
-- per-claim size, not per-person cost, so frequent small claims can look
-- cheap per person while each claim is large -- emits median and mean
-- claim alongside cost per person).
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
)
SELECT
    care_type                                                AS "Type of care",
    ROUND(100 * SUM(patient_paid) / SUM(paid), 1)            AS "Patient share - everyone",
    -- payer mix: how the spend is distributed, not what each type pays
    ROUND(100 * SUM(IFF(payer_type='Government', paid, 0)) / SUM(paid), 1)
                                                             AS "% of spend on government patients",
    ROUND(100 * SUM(IFF(payer_type='Commercial', paid, 0)) / SUM(paid), 1)
                                                             AS "% of spend on commercial patients",
    ROUND(100 * SUM(IFF(payer_type='Self-Pay / Uninsured', paid, 0)) / SUM(paid), 1)
                                                             AS "% of spend on uninsured patients",
    -- claim size, which is what the cap actually acts on
    ROUND(MEDIAN(paid))                                      AS "Median claim",
    ROUND(AVG(paid))                                         AS "Average claim",
    ROUND(SUM(paid) / COUNT(DISTINCT patient_id))            AS "Paid per person",
    ROUND(COUNT(*) * 1.0 / COUNT(DISTINCT patient_id), 1)    AS "Claims per person"
FROM classified
GROUP BY care_type
ORDER BY "Patient share - everyone" DESC;
