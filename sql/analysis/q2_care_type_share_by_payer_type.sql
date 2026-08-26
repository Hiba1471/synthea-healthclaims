-- =====================================================================
-- Q2: for each TYPE OF CARE, how far apart are the insurance types?
--
-- Same question as q2_top10_share_by_payer_type.sql, moved up from single
-- conditions to the 15 care types, and computed differently: the share is
-- calculated SEPARATELY FOR EACH YEAR and then the MEDIAN of the five is
-- taken, so one odd year cannot dominate a pooled ratio.
--
-- Lowest and highest year are emitted alongside so the spread is visible. If
-- they sit close to the median the gap is standing benefit design, not drift.
--
-- NOTE: the care-type CASE below is copied verbatim from
-- q2_patient_cost_by_care_type.sql, which is the canonical definition.
-- Edit the grouping THERE first, then copy it here -- the two must agree or
-- this query and the money ranking will disagree about what "dental" means.
--
-- Results: sql/results/q2_care_type_share_by_payer_type_2020_2024.csv
-- =====================================================================

WITH claim_money AS (
    SELECT
        CLAIM_ID,
        MIN(PATIENT_ID)      AS patient_id,
        MIN(PAYER_TYPE)      AS payer_type,
        MIN(SERVICE_YEAR)    AS service_year,
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
classified AS (
    SELECT
        m.payer_type, m.service_year, m.paid, m.patient_paid,
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
    WHERE cc.condition_code IS NOT NULL
),
yearly AS (
    SELECT
        care_type,
        COALESCE(payer_type, 'Everyone')                  AS payer_type,
        service_year,
        100 * SUM(patient_paid) / NULLIF(SUM(paid), 0)    AS share_pct
    FROM classified
    GROUP BY GROUPING SETS ((care_type, payer_type, service_year),
                            (care_type, service_year))
    HAVING SUM(paid) > 0
),
pooled AS (
    SELECT care_type, 100 * SUM(patient_paid) / NULLIF(SUM(paid), 0) AS pooled_share
    FROM classified GROUP BY care_type
)
SELECT
    y.care_type                             AS "Type of care",
    y.payer_type                            AS "Kind of insurance",
    ROUND(MEDIAN(y.share_pct), 1)           AS "Typical % of the bill the patient pays",
    ROUND(MIN(y.share_pct), 1)              AS "Lowest year",
    ROUND(MAX(y.share_pct), 1)              AS "Highest year",
    COUNT(*)                                AS "Years counted",
    ROUND(p.pooled_share, 1)                AS "All 5 years pooled - everyone"
FROM yearly y
JOIN pooled p ON y.care_type = p.care_type
GROUP BY y.care_type, y.payer_type, p.pooled_share
ORDER BY p.pooled_share DESC, y.payer_type;
