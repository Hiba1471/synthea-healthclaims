-- =====================================================================
-- REFERENCE TABLE, NOT A CORRECTED DATASET: the Q2 care-type breakdown with
-- the eleven confidently-inflated conditions divided down to their
-- real-world benchmark, the other 174 conditions left exactly as billed.
--
-- NOTHING IN THE REPORT IS DRAWN FROM THIS. Written when the plan was to
-- replace the client report's primary Finding 2 charts with price-corrected
-- versions; that plan was cancelled and the primary charts still show real,
-- as-billed data. Kept because of the result below, which is not visible
-- anywhere else in this project.
--
-- THE RESULT WORTH KEEPING: correcting prices moves member-paid SHARE, and
-- not all in one direction. Allergy & immune rises from 10.0% to 15.0%;
-- cancer & tumours falls from 8.3% to 7.4%; kidney & urinary falls from
-- 14.2% to 13.0%; dental from 27.9% to 25.8%. That is the annual
-- out-of-pocket cap doing exactly what q2_commercial_cap_by_care_type.sql
-- and q2_cap_reversal_diagnosis.sql already documented: a large bill blows
-- past the cap so the member's SHARE of it is small, while a smaller bill
-- stays under the cap and the member carries proportionally more of it.
-- Correcting inflated prices downward pushes several categories back under
-- that cap. Categories with no corrected condition in them (blood
-- disorders, diabetes, chronic pain, mental health, other) are unchanged to
-- the decimal, which is the check that the query is doing what it claims.
--
-- METHOD FOR THE PAYER SPLIT, stated because it is a real choice, not a
-- mechanical one. BILLED_AMOUNT, PAID_AMOUNT, PAID_BY_PATIENT and
-- PAID_BY_PAYER are ALL divided by the same condition-specific factor,
-- together, rather than repricing the bill and leaving the paid amounts
-- alone. Consequence: "% of the bill patients pay" for a corrected
-- condition is IDENTICAL to its as-billed value, because both the
-- numerator and denominator of that ratio scale down together. This is a
-- deliberate simplification, not an oversight -- the documented pricing
-- defect is that Synthea prices PROCEDURES at flat, arbitrary amounts
-- regardless of what they are (DATA_ANALYSIS_CONTEXT.md, "Why the prices
-- are wrong"), not that its copay/coinsurance MECHANISM is broken; that
-- mechanism was separately verified against the flat-copay/coinsurance-cap
-- rules and found to work correctly. Rescaling the bill without touching the
-- payer-split logic keeps the one correction to the one thing known to be
-- wrong. What DOES change under this correction is the DOLLAR amount a
-- member paid, not the percentage share.
--
-- Same eleven divisors and codes as q1_multi_condition_sensitivity.sql and
-- q1_condition_breakdown_repriced.sql. The ORIGINAL as-billed
-- q2_patient_cost_by_care_type_2020_2024.csv and its charts are untouched.
--
-- Results: sql/results/q2_care_type_breakdown_repriced_2020_2024.csv
-- =====================================================================

WITH claim_raw AS (
    SELECT
        CLAIM_ID,
        MIN(PATIENT_ID)      AS patient_id,
        MIN(PAYER_TYPE)      AS payer_type,
        SUM(BILLED_AMOUNT)   AS billed_raw,
        SUM(PAID_AMOUNT)     AS paid_raw,
        SUM(PAID_BY_PATIENT) AS patient_paid_raw,
        SUM(PAID_BY_PAYER)   AS insurer_paid_raw
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
claim_money AS (
    SELECT r.CLAIM_ID, r.patient_id, r.payer_type,
        r.billed_raw / f.factor AS billed,
        r.paid_raw / f.factor AS paid,
        r.patient_paid_raw / f.factor AS patient_paid,
        r.insurer_paid_raw / f.factor AS insurer_paid
    FROM claim_raw r
    JOIN claim_condition cc ON r.CLAIM_ID = cc.CLAIM_ID
    CROSS JOIN LATERAL (
        SELECT CASE cc.condition_code
            WHEN '72892002'  THEN 8.587
            WHEN '419199007' THEN 88.976
            WHEN '66383009'  THEN 12.542
            WHEN '18718003'  THEN 7.522
            WHEN '424132000' THEN 11.038
            WHEN '68496003'  THEN 19.736
            WHEN '312608009' THEN 5.285
            WHEN '109570002' THEN 16.564
            WHEN '10509002'  THEN 9.252
            WHEN '230690007' THEN 3.836
            WHEN '307426000' THEN 23.590
            ELSE 1
        END AS factor
    ) f
),
classified AS (
    SELECT
        m.*,
        d.DESCRIPTION AS condition_name,
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
    RANK() OVER (ORDER BY SUM(patient_paid) DESC)          AS "Rank by money PATIENTS PAID",
    RANK() OVER (ORDER BY SUM(billed) DESC)                AS "Rank by TOTAL BILL",
    care_type                                              AS "Type of care",
    COUNT(DISTINCT condition_name)                         AS "Conditions grouped here",
    ROUND(SUM(patient_paid))                               AS "Paid by patients over 5 years",
    ROUND(100 * SUM(patient_paid) / SUM(SUM(patient_paid)) OVER (), 1)
                                                           AS "% of everything patients paid",
    ROUND(100 * SUM(patient_paid) / NULLIF(SUM(paid), 0), 1)
                                                           AS "% of the bill patients pay",
    ROUND(SUM(insurer_paid))                               AS "Paid by insurers",
    ROUND(SUM(billed))                                     AS "Total bill",
    COUNT(DISTINCT patient_id)                             AS "People affected",
    ROUND(SUM(billed) / NULLIF(COUNT(DISTINCT patient_id), 0))
                                                           AS "Total cost per person over 5 years",
    ROUND(SUM(patient_paid) / NULLIF(COUNT(DISTINCT patient_id), 0))
                                                           AS "Of that, paid by the person",
    ROUND(SUM(insurer_paid) / NULLIF(COUNT(DISTINCT patient_id), 0))
                                                           AS "Of that, paid by their insurer",
    -- the same split by insurance, since the blended share hides a large gap
    ROUND(100 * SUM(IFF(payer_type='Commercial', patient_paid, 0))
          / NULLIF(SUM(IFF(payer_type='Commercial', paid, 0)), 0), 1)
                                                           AS "% patients pay - Commercial",
    ROUND(100 * SUM(IFF(payer_type='Government', patient_paid, 0))
          / NULLIF(SUM(IFF(payer_type='Government', paid, 0)), 0), 1)
                                                           AS "% patients pay - Government"
FROM classified
GROUP BY care_type
-- ordered by the share patients carry, not by dollars: the share is what
-- a patient actually experiences, and it is not visible from the money
-- ranking (diabetes is worst on share but 10th on dollars).
ORDER BY SUM(patient_paid) / NULLIF(SUM(paid), 0) DESC;
