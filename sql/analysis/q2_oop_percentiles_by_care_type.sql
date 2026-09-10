-- =====================================================================
-- Q2 extension: for each care type, what does an AFFECTED member
-- actually pay out of pocket -- median, P75, P90 -- not just the share
-- of the bill? q2_patient_cost_by_care_type.sql reports the PERCENTAGE
-- members pay, but a high percentage on a small bill (a nuisance) is not
-- the same as a high percentage on a large bill (real exposure); this
-- adds the dollar side so the two are not conflated. Care-type ladder
-- copied verbatim from q2_patient_cost_by_care_type.sql, so categories
-- match exactly.
-- =====================================================================

WITH claim_money AS (
    SELECT CLAIM_ID, MIN(PATIENT_ID) AS patient_id, SUM(PAID_BY_PATIENT) AS patient_paid
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
classified AS (
    SELECT m.patient_id, m.patient_paid,
        CASE
            WHEN LOWER(d.DESCRIPTION) REGEXP '.*(gingiv|dental|tooth|teeth|molar|jaw|palatinus|temporomandibular|mandible|alveolitis).*' THEN 'Dental & oral'
            WHEN LOWER(d.DESCRIPTION) REGEXP '.*(pregnan|miscarriage|ovum|tubal|newborn|antenatal|postnatal).*' THEN 'Maternity'
            WHEN LOWER(d.DESCRIPTION) REGEXP '.*(malignant|carcinoma|neoplasm|polyp of colon).*' THEN 'Cancer & tumours'
            -- "cholecystitis" contains the substring "cystitis", so the Kidney &
            -- urinary branch below would otherwise claim a gallbladder infection.
            -- Tested first and routed where it belongs.
            WHEN LOWER(d.DESCRIPTION) REGEXP '.*cholecystitis.*' THEN 'Infections (other)'
            WHEN LOWER(d.DESCRIPTION) REGEXP '.*(kidney|renal|cystitis|pyelonephritis|urinary|bladder).*' THEN 'Kidney & urinary'
            WHEN LOWER(d.DESCRIPTION) REGEXP '.*(heart|stroke|myocardial|atrial|aortic|coronary|hypertension|cardiac|circulat).*' THEN 'Heart & circulation'
            WHEN LOWER(d.DESCRIPTION) REGEXP '.*(bronchitis|covid|pharyngitis|sinusitis|sore throat|emphysema|asthma|otitis|respiratory|pneumon|influenza).*' THEN 'Respiratory & ENT'
            WHEN LOWER(d.DESCRIPTION) REGEXP '.*(diabet|obesity|lipid|glycemia|metabolic|triglyceride|osteoporosis|body mass).*' THEN 'Diabetes & metabolic'
            WHEN LOWER(d.DESCRIPTION) REGEXP '.*(drug|alcohol|anxiety|attention deficit|sleep|suicide|overdose|depress|stress).*' THEN 'Mental health & substance use'
            WHEN LOWER(d.DESCRIPTION) REGEXP '.*(injury|fracture|sprain|laceration|burn|concussion|rupture|dislocation|wound).*' THEN 'Injury & trauma'
            WHEN LOWER(d.DESCRIPTION) REGEXP '.*allerg.*' THEN 'Allergy & immune'
            WHEN LOWER(d.DESCRIPTION) REGEXP '.*(seizure|alzheimer|neuropathy|epilep|dementia).*' THEN 'Brain & nervous system'
            WHEN LOWER(d.DESCRIPTION) REGEXP '.*(sepsis|immunodeficiency|appendicitis|cholecystitis|infection|infective|viral|bacterial).*' THEN 'Infections (other)'
            WHEN LOWER(d.DESCRIPTION) REGEXP '.*(anemia|anaemia).*' THEN 'Blood disorders'
            WHEN LOWER(d.DESCRIPTION) REGEXP '.*pain.*' THEN 'Chronic pain'
            ELSE 'Other'
        END AS care_type
    FROM claim_money m
    JOIN claim_condition cc ON m.CLAIM_ID = cc.CLAIM_ID
    JOIN SYNTHEA_HEALTHCLAIMS.PUBLIC.CODE_DICTIONARY d ON cc.condition_code = d.CODE
    WHERE cc.condition_code IS NOT NULL
),
per_patient AS (
    -- five-year total paid by each affected patient, within this care type
    SELECT care_type, patient_id, SUM(patient_paid) AS oop
    FROM classified
    GROUP BY care_type, patient_id
)
SELECT
    care_type                                        AS "Type of care",
    COUNT(*)                                          AS "People affected",
    ROUND(MEDIAN(oop))                                AS "Median OOP over 5 years",
    ROUND(PERCENTILE_CONT(0.75) WITHIN GROUP (ORDER BY oop)) AS "P75 OOP over 5 years",
    ROUND(PERCENTILE_CONT(0.90) WITHIN GROUP (ORDER BY oop)) AS "P90 OOP over 5 years",
    ROUND(AVG(oop))                                   AS "Mean OOP over 5 years"
FROM per_patient
GROUP BY care_type
ORDER BY "Median OOP over 5 years" DESC;
