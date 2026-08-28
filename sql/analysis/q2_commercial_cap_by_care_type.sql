-- =====================================================================
-- Q2: which types of care sit above the point where commercial patients
--     stop paying?
--
-- Commercial patients pay roughly half of a small claim and very little of a
-- large one. The reason is NOT a per-claim rule that switches off at some
-- threshold. It is that on larger claims a growing FRACTION of patients have
-- already exhausted their annual out-of-pocket maximum and so pay nothing at
-- all, which drags the aggregate share down. Measured in $500 bands, the
-- share of commercial claims where the patient pays exactly zero climbs from
-- ~15% around $3,500 to ~67% around $8,000, and the aggregate patient share
-- falls from ~54% to ~16% across the same range. It is a taper, not a cliff.
--
-- $5,000 is used below as a reporting split because it is roughly where the
-- zero-paying group becomes the majority. It is a convenient line, not a rule
-- in the data -- nothing changes discontinuously there.
--
-- Government patients are excluded: they pay a flat $0-50 regardless of claim
-- size, so the cap question does not arise for them.
--
-- Taxonomy CASE copied verbatim from q2_patient_cost_by_care_type.sql, which
-- stays canonical. Edit there first, then copy here.
--
-- Results: sql/results/q2_commercial_cap_by_care_type_2020_2024.csv
-- =====================================================================

WITH claim_money AS (
    SELECT CLAIM_ID,
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
    SELECT m.paid, m.patient_paid,
        CASE
            WHEN LOWER(d.DESCRIPTION) REGEXP '.*(gingiv|dental|tooth|teeth|molar|jaw|palatinus|temporomandibular|mandible|alveolitis).*'
                THEN 'Dental & oral'
            WHEN LOWER(d.DESCRIPTION) REGEXP '.*(pregnan|miscarriage|ovum|tubal|newborn|antenatal|postnatal).*'
                THEN 'Maternity'
            WHEN LOWER(d.DESCRIPTION) REGEXP '.*(malignant|carcinoma|neoplasm|polyp of colon).*'
                THEN 'Cancer & tumours'
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
    WHERE m.payer_type = 'Commercial' AND cc.condition_code IS NOT NULL
)
SELECT
    care_type                                                   AS "Type of care",
    COUNT(*)                                                    AS "Commercial claims",
    ROUND(SUM(paid))                                            AS "Total paid",
    ROUND(100 * SUM(IFF(paid > 5000, paid, 0)) / SUM(paid), 1)  AS "% of spend on claims over $5,000",
    ROUND(100 * AVG(IFF(paid > 5000, 1, 0)), 1)                 AS "% of claims over $5,000",
    ROUND(100 * SUM(IFF(paid <= 5000, patient_paid, 0))
              / NULLIF(SUM(IFF(paid <= 5000, paid, 0)), 0), 1)  AS "Patient share under $5,000",
    ROUND(100 * SUM(IFF(paid > 5000, patient_paid, 0))
              / NULLIF(SUM(IFF(paid > 5000, paid, 0)), 0), 1)   AS "Patient share over $5,000",
    ROUND(100 * AVG(IFF(patient_paid = 0, 1, 0)), 1)            AS "% of claims patient pays nothing"
FROM classified
GROUP BY care_type
HAVING COUNT(*) >= 1000
ORDER BY "% of spend on claims over $5,000" DESC;
