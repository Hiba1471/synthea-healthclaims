-- =====================================================================
-- SYNTHEA_HEALTHCLAIMS.PUBLIC.CODE_DICTIONARY  (pass 1 of 2 -- raw build)
--
-- One row per clinical code seen anywhere in the share, with a single
-- canonical description. Solves:
--   #4  DIAGNOSIS1 / PROCEDURECODE mix code systems, so ~30% of diagnosis
--       spend will not join to CONDITIONS.CODE alone.
--   #19 the same code appears with several spellings
--       ("Encounter for Problem" / "for problem" / "for problem (procedure)").
--
-- Built as a TABLE, not a view: it is small, it saves re-scanning ~356M rows
-- on every lookup, and it can be hand-corrected where the derived
-- classification is wrong.
--
-- SOURCE COVERAGE NOTE (revised):
--   The first build excluded OBSERVATIONS (LOINC), IMAGING_STUDIES (DICOM)
--   and MEDICATIONS.CODE (RxNorm) on the grounds that those code spaces
--   "can never appear in a diagnosis field". That held for DIAGNOSIS1-8,
--   which resolve 100%. But it was over-generalised: CLAIMS_TX.PROCEDURECODE
--   draws on them too, leaving 402 codes and $5.72B unresolved.
--   MEDICATIONS.CODE (444 numeric RxNorm codes) and
--   IMAGING_STUDIES.BODYSITE_CODE (14) are now included.
--
-- Still excluded, and correctly so -- these are TEXT columns, while every
-- code field we resolve (DIAGNOSIS1-8, PROCEDURECODE) is NUMBER, so they
-- could never match even if unioned:
--   OBSERVATIONS.CODE            LOINC, e.g. '8302-2'  (TEXT)
--   IMAGING_STUDIES.MODALITY_CODE, SOP_CODE  DICOM     (TEXT)
-- IMAGING_STUDIES.PROCEDURE_CODE is numeric but has no paired description
-- column, so there is nothing to look up.
--
-- SEMANTIC_TAG is the trailing parenthesised qualifier SNOMED puts on its
-- fully specified names -- (disorder), (procedure), (finding), (situation),
-- (environment), (substance). It is a real classification carried by the
-- data, which is what pass 2 uses instead of keyword guesswork.
-- =====================================================================

CREATE OR REPLACE TABLE SYNTHEA_HEALTHCLAIMS.PUBLIC.CODE_DICTIONARY AS
WITH raw AS (
    SELECT CODE AS code, DESCRIPTION AS descr, 'CONDITIONS' AS src
      FROM SYNTHETIC_HEALTHCARE_DATA_CLINICAL_AND_CLAIMS.SILVER.CONDITIONS
    UNION ALL
    SELECT CODE, DESCRIPTION, 'ENCOUNTERS'
      FROM SYNTHETIC_HEALTHCARE_DATA_CLINICAL_AND_CLAIMS.SILVER.ENCOUNTERS
    UNION ALL
    SELECT REASONCODE, REASONDESCRIPTION, 'ENCOUNTERS.REASON'
      FROM SYNTHETIC_HEALTHCARE_DATA_CLINICAL_AND_CLAIMS.SILVER.ENCOUNTERS
     WHERE REASONCODE IS NOT NULL
    UNION ALL
    SELECT CODE, DESCRIPTION, 'PROCEDURES'
      FROM SYNTHETIC_HEALTHCARE_DATA_CLINICAL_AND_CLAIMS.SILVER.PROCEDURES
    UNION ALL
    SELECT REASONCODE, REASONDESCRIPTION, 'PROCEDURES.REASON'
      FROM SYNTHETIC_HEALTHCARE_DATA_CLINICAL_AND_CLAIMS.SILVER.PROCEDURES
     WHERE REASONCODE IS NOT NULL
    UNION ALL
    SELECT CODE, DESCRIPTION, 'CARE_PLANS'
      FROM SYNTHETIC_HEALTHCARE_DATA_CLINICAL_AND_CLAIMS.SILVER.CARE_PLANS
    UNION ALL
    SELECT REASONCODE, REASONDESCRIPTION, 'CARE_PLANS.REASON'
      FROM SYNTHETIC_HEALTHCARE_DATA_CLINICAL_AND_CLAIMS.SILVER.CARE_PLANS
     WHERE REASONCODE IS NOT NULL
    UNION ALL
    SELECT CODE, DESCRIPTION, 'ALLERGIES'
      FROM SYNTHETIC_HEALTHCARE_DATA_CLINICAL_AND_CLAIMS.SILVER.ALLERGIES
    UNION ALL
    SELECT CODE, DESCRIPTION, 'IMMUNIZATIONS'
      FROM SYNTHETIC_HEALTHCARE_DATA_CLINICAL_AND_CLAIMS.SILVER.IMMUNIZATIONS
    UNION ALL
    SELECT CODE, DESCRIPTION, 'DEVICES'
      FROM SYNTHETIC_HEALTHCARE_DATA_CLINICAL_AND_CLAIMS.SILVER.DEVICES
    UNION ALL
    SELECT CODE, DESCRIPTION, 'SUPPLIES'
      FROM SYNTHETIC_HEALTHCARE_DATA_CLINICAL_AND_CLAIMS.SILVER.SUPPLIES
    UNION ALL
    SELECT REASONCODE, REASONDESCRIPTION, 'MEDICATIONS.REASON'
      FROM SYNTHETIC_HEALTHCARE_DATA_CLINICAL_AND_CLAIMS.SILVER.MEDICATIONS
     WHERE REASONCODE IS NOT NULL
    -- added to close the PROCEDURECODE gap (402 codes / $5.72B)
    UNION ALL
    SELECT CODE, DESCRIPTION, 'MEDICATIONS'
      FROM SYNTHETIC_HEALTHCARE_DATA_CLINICAL_AND_CLAIMS.SILVER.MEDICATIONS
    UNION ALL
    SELECT BODYSITE_CODE, BODYSITE_DESCRIPTION, 'IMAGING_STUDIES'
      FROM SYNTHETIC_HEALTHCARE_DATA_CLINICAL_AND_CLAIMS.SILVER.IMAGING_STUDIES
     WHERE BODYSITE_CODE IS NOT NULL
),
per_code AS (
    SELECT
        code,
        MODE(descr)                        AS canonical_description,
        COUNT(*)                           AS occurrence_count,
        COUNT(DISTINCT descr)              AS description_variants,
        LISTAGG(DISTINCT src, ', ')
            WITHIN GROUP (ORDER BY src)    AS source_tables
    FROM raw
    WHERE code IS NOT NULL
      AND descr IS NOT NULL
    GROUP BY code
)
SELECT
    code                                   AS CODE,
    canonical_description                  AS DESCRIPTION,
    -- trailing "(...)" qualifier, e.g. disorder / procedure / finding
    LOWER(REGEXP_SUBSTR(canonical_description, '\\(([^()]+)\\)$', 1, 1, 'e', 1))
                                           AS SEMANTIC_TAG,
    source_tables                          AS SOURCE_TABLES,
    description_variants                   AS DESCRIPTION_VARIANTS,
    occurrence_count                       AS OCCURRENCE_COUNT
FROM per_code;
