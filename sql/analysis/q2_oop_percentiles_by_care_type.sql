-- =====================================================================
-- Q2 EXTENSION: for each type of care, what does the AFFECTED MEMBER actually
-- pay out of pocket -- median, P75, P90 -- not just the share of the bill?
--
-- WHY THIS EXISTS. q2_patient_cost_by_care_type.sql reports the PERCENTAGE of
-- each care type's bill that members pay, and DATA_ANALYSIS_CONTEXT.md is
-- explicit that a high percentage on a small bill is not the same problem as
-- a high percentage on a large one. This query adds the dollar side: for a
-- member who actually has a claim in that care type, what did they pay,
-- typically (median) and at the high end (P75, P90)? A high SHARE with a low
-- MEDIAN DOLLAR AMOUNT is a nuisance; a high share with a high median dollar
-- amount is a real financial exposure. The two are not interchangeable, and
-- the report should not use "share" language ("burden", "falls hardest") to
-- describe a pattern that is only shown here in percentage terms.
--
-- care_type classification is copied verbatim from
-- q2_patient_cost_by_care_type.sql so the two files' categories match exactly.
--
-- Results: sql/results/q2_oop_percentiles_by_care_type_2020_2024.csv
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
