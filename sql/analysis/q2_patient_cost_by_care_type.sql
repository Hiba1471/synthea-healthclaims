-- =====================================================================
-- Q2: which TYPES OF CARE do patients pay the most for?
--
-- Groups the 183 individual conditions into clinical care types, which is a
-- more useful unit than a single condition: "dental" is one budget, one
-- benefit design and one policy lever, even though it appears in the data as
-- eleven separate conditions.
--
-- The grouping is a keyword classification over the condition name,
-- deliberately written out in full so it can be read and corrected. Order
-- matters -- dental is tested first so "infection of tooth" and "fracture of
-- mandible" group as dental rather than as infection or injury.
--
-- Dental is split into PREVENTIVE and RESTORATIVE. Two judgment calls sit in
-- that split and both are reversible by moving one keyword:
--
--   1. "Primary dental caries" is RESTORATIVE. Caries is the textbook
--      preventable condition, but once it is diagnosed and billed the care is
--      a filling. Moving it to preventive is a large swing -- it is the second
--      biggest dental condition -- so the choice is stated rather than buried.
--   2. Jaw and TMJ trauma (fracture of mandible, dislocations) is RESTORATIVE
--      rather than Injury & trauma, which keeps the pre-existing convention
--      that dental is tested before injury. Delete the jaw/mandible/
--      temporomandibular keywords from the dental branch to route it back.
--
-- Anything unmatched falls to "Other", which is reported rather than hidden
-- so the coverage of the taxonomy is visible.
--
-- Results: sql/results/q2_patient_cost_by_care_type_2020_2024.csv
-- =====================================================================

WITH claim_money AS (
    SELECT
        CLAIM_ID,
        MIN(PATIENT_ID)      AS patient_id,
        MIN(PAYER_TYPE)      AS payer_type,
        SUM(BILLED_AMOUNT)   AS billed,
        SUM(PAID_AMOUNT)     AS paid,
        SUM(PAID_BY_PATIENT) AS patient_paid,
        SUM(PAID_BY_PAYER)   AS insurer_paid
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
        m.*,
        d.DESCRIPTION AS condition_name,
        CASE
            -- Dental splits two ways. Preventive is tested first: gum disease and
            -- torus palatinus are managed by cleaning, monitoring and hygiene,
            -- with no tooth structure restored. Everything else dental falls to
            -- restorative -- repairing or replacing structure that is already
            -- damaged. See the header note for the two judgment calls.
            WHEN LOWER(d.DESCRIPTION) REGEXP '.*(gingiv|palatinus).*'
                THEN 'Dental - preventive'
            WHEN LOWER(d.DESCRIPTION) REGEXP '.*(dental|tooth|teeth|molar|jaw|temporomandibular|mandible|alveolitis).*'
                THEN 'Dental - restorative'
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
