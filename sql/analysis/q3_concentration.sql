-- =====================================================================
-- Q3: how concentrated is spend? North star: top N% of PATIENTS vs. X%
-- of spend; same Pareto for CONDITIONS, ORGANISATIONS and CARE TYPES, to
-- see whether spend is driven by a few sick patients, expensive
-- conditions, high-volume providers, or kinds of care.
--
-- Read the denominators before comparing rows: patients and
-- organisations cover all $99.11B, but conditions and care types cover
-- only the $72.69B with a real diagnosis attached. Also read entity
-- count alongside every percentage -- with only 15 care types, any one
-- is a large slice by construction (the same reason payers, with only
-- 10 entities, were rejected as a grain). Aggregate to entity level once
-- per grain, then window over that small result -- never re-scan the
-- fact table per bucket.
-- =====================================================================

WITH base AS (
    SELECT CLAIM_ID, PATIENT_ID, ENCOUNTER_ID, BILLED_AMOUNT
    FROM SYNTHEA_HEALTHCLAIMS.PUBLIC.V_CLAIMS_TX_CLEAN
    WHERE NOT IS_ADMIN_NOISE_CODE
      AND PROCEDURECODE IS NOT NULL
      AND BILLED_AMOUNT > 0
),

-- ---- grain 1: patients -------------------------------------------------
patient_totals AS (
    SELECT 'Patients' AS grain, PATIENT_ID AS entity, SUM(BILLED_AMOUNT) AS amt
    FROM base GROUP BY PATIENT_ID
),

-- ---- grain 2: conditions (same dx1 -> dx2 fallback as Q1) ---------------
claim_condition AS (
    SELECT
        c.CLAIM_ID,
        CASE WHEN d1.IS_CONDITION THEN c.DIAGNOSIS1
             WHEN d2.IS_CONDITION THEN c.DIAGNOSIS2 END AS condition_code
    FROM SYNTHETIC_HEALTHCARE_DATA_CLINICAL_AND_CLAIMS.SILVER.CLAIMS c
    LEFT JOIN SYNTHEA_HEALTHCLAIMS.PUBLIC.CODE_DICTIONARY d1 ON c.DIAGNOSIS1 = d1.CODE
    LEFT JOIN SYNTHEA_HEALTHCLAIMS.PUBLIC.CODE_DICTIONARY d2 ON c.DIAGNOSIS2 = d2.CODE
),
condition_totals AS (
    SELECT 'Conditions' AS grain, cc.condition_code AS entity, SUM(b.BILLED_AMOUNT) AS amt
    FROM base b
    JOIN claim_condition cc ON b.CLAIM_ID = cc.CLAIM_ID
    WHERE cc.condition_code IS NOT NULL
    GROUP BY cc.condition_code
),

-- ---- grain 3: organisations (view lacks ORG, so join ENCOUNTERS) --------
org_totals AS (
    SELECT 'Organisations' AS grain, e.ORGANIZATION_ID AS entity, SUM(b.BILLED_AMOUNT) AS amt
    FROM base b
    JOIN SYNTHETIC_HEALTHCARE_DATA_CLINICAL_AND_CLAIMS.SILVER.ENCOUNTERS e
      ON b.ENCOUNTER_ID = e.ENCOUNTER_ID
    GROUP BY e.ORGANIZATION_ID
),

-- ---- grain 4: care types (the 185 conditions grouped into 15) -----------
-- Taxonomy CASE copied verbatim from q2_patient_cost_by_care_type.sql, which
-- stays canonical. Edit there first, then copy here.
care_type_totals AS (
    SELECT 'Care types' AS grain,
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
            END AS entity,
           SUM(b.BILLED_AMOUNT) AS amt
    FROM base b
    JOIN claim_condition cc ON b.CLAIM_ID = cc.CLAIM_ID
    JOIN SYNTHEA_HEALTHCLAIMS.PUBLIC.CODE_DICTIONARY d ON cc.condition_code = d.CODE
    WHERE cc.condition_code IS NOT NULL
    GROUP BY 2
),

stacked AS (
    SELECT * FROM patient_totals
    UNION ALL SELECT * FROM condition_totals
    UNION ALL SELECT * FROM org_totals
    UNION ALL SELECT * FROM care_type_totals
),
ranked AS (
    SELECT
        grain,
        amt,
        ROW_NUMBER() OVER (PARTITION BY grain ORDER BY amt DESC)      AS rn,
        COUNT(*)    OVER (PARTITION BY grain)                         AS n_entities,
        SUM(amt)    OVER (PARTITION BY grain)                         AS grain_total,
        SUM(amt)    OVER (PARTITION BY grain ORDER BY amt DESC
                          ROWS BETWEEN UNBOUNDED PRECEDING
                                   AND CURRENT ROW)                   AS cum_amt
    FROM stacked
),
scored AS (
    SELECT grain, n_entities, grain_total,
           rn / n_entities        AS entity_pctile,
           cum_amt / grain_total  AS cum_share
    FROM ranked
)
SELECT
    grain                                                    AS "Ranked by",
    n_entities                                               AS "How many exist",
    ROUND(grain_total)                                       AS "Total spend",

    -- "the priciest 1% of them run up X% of the bill"
    ROUND(100 * MAX(CASE WHEN entity_pctile <= 0.01 THEN cum_share END), 1)
        AS "Priciest 1% run up this % of spend",
    ROUND(100 * MAX(CASE WHEN entity_pctile <= 0.05 THEN cum_share END), 1)
        AS "Priciest 5% run up this % of spend",
    ROUND(100 * MAX(CASE WHEN entity_pctile <= 0.10 THEN cum_share END), 1)
        AS "Priciest 10% run up this % of spend",
    ROUND(100 * MAX(CASE WHEN entity_pctile <= 0.20 THEN cum_share END), 1)
        AS "Priciest 20% run up this % of spend",
    ROUND(100 * MAX(CASE WHEN entity_pctile <= 0.50 THEN cum_share END), 1)
        AS "Priciest 50% run up this % of spend",

    -- same data flipped: how few does it take to reach half / most of the money
    ROUND(100 * MIN(CASE WHEN cum_share >= 0.50 THEN entity_pctile END), 2)
        AS "% of them needed to reach half the spend",
    ROUND(n_entities * MIN(CASE WHEN cum_share >= 0.50 THEN entity_pctile END))
        AS "= this many of them",
    ROUND(100 * MIN(CASE WHEN cum_share >= 0.80 THEN entity_pctile END), 2)
        AS "% of them needed to reach 80% of spend",
    ROUND(n_entities * MIN(CASE WHEN cum_share >= 0.80 THEN entity_pctile END))
        AS "= this many of them "
FROM scored
GROUP BY grain, n_entities, grain_total
ORDER BY CASE grain WHEN 'Patients' THEN 1 WHEN 'Conditions' THEN 2 ELSE 3 END;
