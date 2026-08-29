-- =====================================================================
-- Q2 FOLLOW-UP: does the cheap-care/high-share pattern survive inside a
--               single payer type?
--
-- Across all 15 care types, patient share tracks cost per person at Spearman
-- -0.60. But it tracks the SHARE OF SPEND ON GOVERNMENT PATIENTS almost as
-- strongly, at -0.57 -- and government patients pay a flat $0-50 whatever the
-- bill. So the headline relationship may be two effects wearing one number:
--
--   (a) genuine cost-sharing -- cheap care stays under the annual
--       out-of-pocket maximum, so patients keep paying for it, and
--   (b) payer mix -- care types weighted towards government patients read
--       low-share regardless of what they cost.
--
-- Splitting by payer type separates them. WITHIN one payer type the mix is
-- constant by construction, so any surviving cost/share relationship is (a).
-- If the relationship collapses inside each payer type, the headline was
-- mostly (b) and the cost story is weaker than the report currently claims.
--
-- Government is emitted alongside commercial as a control. Its share should be
-- near zero and near flat at every cost level -- if it is not, the flat-copay
-- reading of government cost-sharing is itself wrong.
--
-- Uninsured are excluded: they pay 100% by definition, so there is no share to
-- vary and no cap to reach. THIS MATTERS WHEN COMPARING BACK TO THE BLENDED
-- FIGURES. The blend is government + commercial + uninsured, so it is dragged
-- down by government and up by uninsured. For Maternity, Allergy & immune and
-- Kidney & urinary the blended share comes out ABOVE the commercial share
-- (17.0 vs 15.1, 10.0 vs 6.7, 14.2 vs 14.3) purely because uninsured patients
-- are 7-9% of spend in those groups and pay everything. Nothing about
-- commercial cost-sharing changed; the blend simply contains a different mix.
--
-- WHAT THIS RETURNED
--
-- The pattern survives and sharpens. Share tracks cost per person at -0.72
-- among commercial patients and -0.88 among government, against -0.60 blended.
-- Payer mix was damping the relationship, not manufacturing it, because
-- averaging two populations with very different payment levels adds noise.
--
-- The clearest single result is Brain & nervous system, which was the apparent
-- counter-example to the whole cheap-care/high-share rule: cheap at $8,939 per
-- person yet only 8.5% patient share. Split by payer it reads 40.2% commercial.
-- It is not an exception at all -- it is 90.2% government-funded spend, and
-- those near-zero payments were swamping everyone else's. Most care types
-- roughly double: Diabetes 36.6 -> 74.4, Dental 27.9 -> 52.9, Heart 14.7 -> 29.7.
--
-- The government column is included as a control and behaves as predicted: a
-- flat $0-50 copay against a growing bill, so share falls from 8.1% to 0.6%
-- across the cost range and never exceeds 8.1%. That -0.88 is arithmetic
-- rather than behaviour, and should not be quoted as evidence of anything
-- beyond the copay being flat.
--
-- The practical consequence is that the blended per-care-type share is nobody's
-- experience. Commercial patients span 6.7% to 74.4%, government 0.6% to 8.1%.
-- Quoting diabetes care's blended 36.6% describes no actual patient.
--
-- Taxonomy CASE copied verbatim from q2_patient_cost_by_care_type.sql, which
-- stays canonical. Edit there first, then copy here.
--
-- Results: sql/results/q2_pattern_within_payer_2020_2024.csv
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
