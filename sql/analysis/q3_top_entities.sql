-- =====================================================================
-- Q3 DETAIL: WHICH hospitals and WHICH conditions drive the spend?
--
-- q3_concentration.sql establishes that 86 sites and 2 conditions cover
-- half of all spending. This names them.
--
-- Long format so both lists live in one result set:
--   Entity Type = 'Hospital' | 'Condition'
-- Results: sql/results/q3_top_entities_2020_2024.csv
-- =====================================================================

WITH base AS (
    SELECT CLAIM_ID, PATIENT_ID, ENCOUNTER_ID, BILLED_AMOUNT, PAID_BY_PATIENT, PAID_AMOUNT
    FROM SYNTHEA_HEALTHCLAIMS.PUBLIC.V_CLAIMS_TX_CLEAN
    WHERE NOT IS_ADMIN_NOISE_CODE
      AND PROCEDURECODE IS NOT NULL
      AND BILLED_AMOUNT > 0
),

hospitals AS (
    SELECT
        'Hospital'                                   AS entity_type,
        o.NAME || '  (' || o.CITY || ', ' || o.STATE || ')' AS entity,
        SUM(b.BILLED_AMOUNT)                         AS billed,
        COUNT(DISTINCT b.PATIENT_ID)                 AS patients,
        COUNT(DISTINCT b.ENCOUNTER_ID)               AS encounters,
        SUM(b.PAID_BY_PATIENT)                       AS patient_paid,
        SUM(b.PAID_AMOUNT)                           AS paid
    FROM base b
    JOIN SYNTHETIC_HEALTHCARE_DATA_CLINICAL_AND_CLAIMS.SILVER.ENCOUNTERS e
      ON b.ENCOUNTER_ID = e.ENCOUNTER_ID
    JOIN SYNTHETIC_HEALTHCARE_DATA_CLINICAL_AND_CLAIMS.SILVER.ORGANIZATIONS o
      ON e.ORGANIZATION_ID = o.ORGANIZATION_ID
    GROUP BY o.NAME, o.CITY, o.STATE
),

claim_condition AS (
    SELECT c.CLAIM_ID,
           CASE WHEN d1.IS_CONDITION THEN c.DIAGNOSIS1
                WHEN d2.IS_CONDITION THEN c.DIAGNOSIS2 END AS condition_code
    FROM SYNTHETIC_HEALTHCARE_DATA_CLINICAL_AND_CLAIMS.SILVER.CLAIMS c
    LEFT JOIN SYNTHEA_HEALTHCLAIMS.PUBLIC.CODE_DICTIONARY d1 ON c.DIAGNOSIS1 = d1.CODE
    LEFT JOIN SYNTHEA_HEALTHCLAIMS.PUBLIC.CODE_DICTIONARY d2 ON c.DIAGNOSIS2 = d2.CODE
),
conditions AS (
    SELECT
        'Condition'                                  AS entity_type,
        d.DESCRIPTION                                AS entity,
        SUM(b.BILLED_AMOUNT)                         AS billed,
        COUNT(DISTINCT b.PATIENT_ID)                 AS patients,
        COUNT(DISTINCT b.ENCOUNTER_ID)               AS encounters,
        SUM(b.PAID_BY_PATIENT)                       AS patient_paid,
        SUM(b.PAID_AMOUNT)                           AS paid
    FROM base b
    JOIN claim_condition cc ON b.CLAIM_ID = cc.CLAIM_ID
    JOIN SYNTHEA_HEALTHCLAIMS.PUBLIC.CODE_DICTIONARY d ON cc.condition_code = d.CODE
    WHERE cc.condition_code IS NOT NULL
    GROUP BY d.DESCRIPTION
),

stacked AS (
    SELECT * FROM hospitals
    UNION ALL SELECT * FROM conditions
),
ranked AS (
    SELECT stacked.*,
           ROW_NUMBER() OVER (PARTITION BY entity_type ORDER BY billed DESC) AS rnk,
           SUM(billed) OVER (PARTITION BY entity_type)                       AS type_total,
           SUM(billed) OVER (PARTITION BY entity_type ORDER BY billed DESC
                             ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS cum_billed
    FROM stacked
)
SELECT
    entity_type                                        AS "Entity Type",
    rnk                                                AS "Rank",
    entity                                             AS "Name",
    ROUND(billed)                                      AS "Total Billed",
    ROUND(100 * billed / type_total, 2)                AS "% of Type Spend",
    ROUND(100 * cum_billed / type_total, 1)            AS "Running % of Type Spend",
    patients                                           AS "Patients",
    encounters                                         AS "Encounters",
    ROUND(billed / NULLIF(patients, 0))                AS "Billed per Patient",
    ROUND(100 * patient_paid / NULLIF(paid, 0), 1)     AS "% Borne by Patient"
FROM ranked
WHERE rnk <= 25
ORDER BY entity_type, rnk;
