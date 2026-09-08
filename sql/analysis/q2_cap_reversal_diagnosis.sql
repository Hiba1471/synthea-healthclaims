-- =====================================================================
-- Q2 FOLLOW-UP: why do three care types run BACKWARDS against the cap?
--
-- q2_commercial_cap_by_care_type.sql shows commercial patients paying a
-- smaller share of large claims than small ones almost everywhere, because on
-- large claims a growing fraction of patients have already exhausted their
-- annual out-of-pocket maximum. Three care types invert that:
--
--     Kidney & urinary    12.8% under $5,000 -> 38.6% over   (+26 pts)
--     Cancer & tumours    11.0% under        -> 17.8% over   (+ 7 pts)
--     Maternity            7.7% under        -> 15.3% over   (+ 8 pts)
--
-- HYPOTHESIS: this is a composition effect, not a cost-sharing one. A care
-- type is a bag of conditions, and if the conditions that produce small claims
-- are different from the conditions that produce large ones, the two sides of
-- the split are not the same care being priced differently -- they are
-- different care entirely.
--
-- This query tests that by breaking each reversed care type down to the
-- condition level, on both sides of the $5,000 line. If the hypothesis holds,
-- the conditions dominating the cheap side will be largely absent from the
-- dear side and vice versa. If instead the SAME conditions appear on both
-- sides with the share still rising, the effect is real cost-sharing
-- behaviour and needs a different explanation.
--
-- Commercial only, for the same reason as the parent query: government
-- patients pay a flat $0-50 regardless of claim size.
--
-- Taxonomy CASE copied verbatim from q2_patient_cost_by_care_type.sql, which
-- stays canonical. Edit there first, then copy here.
--
-- Results: sql/results/q2_cap_reversal_diagnosis_2020_2024.csv
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
    SELECT m.paid, m.patient_paid, d.DESCRIPTION AS condition_name,
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
    WHERE m.payer_type = 'Commercial' AND cc.condition_code IS NOT NULL
),
reversed_only AS (
    -- label the side once, so it can be grouped and partitioned on
    SELECT paid, patient_paid, condition_name, care_type,
           IFF(paid > 5000, 'over $5,000', 'under $5,000') AS side
    FROM classified
    WHERE care_type IN ('Kidney & urinary', 'Cancer & tumours', 'Maternity')
)
SELECT
    care_type                                     AS "Type of care",
    side                                          AS "Side of the line",
    condition_name                                AS "Condition",
    COUNT(*)                                      AS "Claims",
    ROUND(SUM(paid))                              AS "Paid",
    ROUND(100 * SUM(paid)
          / SUM(SUM(paid)) OVER (PARTITION BY care_type, side), 1)
                                                  AS "% of that side's spend",
    ROUND(AVG(paid))                              AS "Average claim",
    ROUND(100 * SUM(patient_paid) / NULLIF(SUM(paid), 0), 1)
                                                  AS "Patient share",
    ROUND(100 * AVG(IFF(patient_paid = 0, 1, 0)), 1)
                                                  AS "% of claims patient pays nothing"
FROM reversed_only
GROUP BY care_type, side, condition_name
HAVING COUNT(*) >= 500
ORDER BY care_type, side DESC, SUM(paid) DESC;
