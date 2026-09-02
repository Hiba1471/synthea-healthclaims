-- =====================================================================
-- REFERENCE TABLE, NOT USED BY THE REPORT'S PRIMARY CHARTS. The report's
-- Finding 2 charts show real, as-billed data -- a decision reaffirmed after
-- briefly trying the opposite; see the appendix section of the report for
-- how price correction is actually surfaced (a side-by-side comparison
-- table, not a chart swap). This query is the price-corrected companion to
-- q2_oop_percentiles_by_care_type.sql anyway, because of what it found.
--
-- What an AFFECTED member actually paid out of pocket, by type of care,
-- with the eleven documented pricing gaps corrected and the other 174
-- conditions left as billed. Same eleven factors as
-- q1_multi_condition_sensitivity.sql, applied to PAID_BY_PATIENT.
--
-- THE RESULT: maternity's out-of-pocket dollar figure, the one this
-- project has repeatedly cited as the standout example of real financial
-- exposure, is mostly the pricing defect, not a finding about members.
--
--   Maternity      median $10,765 -> $1,308     P90 $64,681 -> $7,630
--   Dental & oral  median  $1,358 -> $144        P90  $9,497 -> $1,379
--   everything else                              unchanged, because those
--                                                 categories contain no
--                                                 corrected condition
--
-- Corrected, infections (other) carries the highest median at $1,456,
-- itself unchanged because nothing in that category was corrected. Do not
-- restate "maternity carries by far the highest dollar exposure" as
-- ground truth without this caveat sitting next to it.
--
-- Results: sql/results/q2_oop_percentiles_repriced_2020_2024.csv
-- =====================================================================

WITH claim_money AS (
    SELECT CLAIM_ID, MIN(PATIENT_ID) AS patient_id, SUM(PAID_BY_PATIENT) AS patient_paid_raw
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
    SELECT m.patient_id,
        m.patient_paid_raw * CASE cc.condition_code
            WHEN '72892002' THEN 0.116 WHEN '66383009' THEN 0.067 WHEN '424132000' THEN 0.091
            WHEN '109570002' THEN 0.059 WHEN '68496003' THEN 0.050 WHEN '419199007' THEN 0.011
            WHEN '18718003' THEN 0.133 WHEN '312608009' THEN 0.189 WHEN '10509002' THEN 0.108
            WHEN '230690007' THEN 0.261 WHEN '307426000' THEN 0.042 ELSE 1.0 END AS patient_paid,
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
