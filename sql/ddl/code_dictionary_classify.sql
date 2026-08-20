-- =====================================================================
-- SYNTHEA_HEALTHCLAIMS.PUBLIC.CODE_DICTIONARY  (pass 2 of 2 -- classification)
--
-- Adds the flags that let DIAGNOSIS1 be ranked as clinical conditions
-- without visit types, paperwork or employment status in the results.
--
-- Columns added:
--   CODE_CATEGORY  Condition / Procedure / Encounter type / Medication or
--                  vaccine / Device or supply / Substance / Social
--                  determinant / Administrative / Other
--   IS_CLINICAL    broad: excludes social, administrative, devices, venues
--   IS_CONDITION   narrow: a diagnosable condition. THIS is the flag for
--                  "rank conditions by cost".
--   CLASSIFIED_BY  semantic_tag / provenance / manual_override -- every row
--                  records how it was decided, so the logic is auditable.
--
-- Both flags exist because "clinical" and "condition" are different
-- questions. A knee replacement is clinical but is not a condition; ranking
-- conditions by cost needs IS_CONDITION.
--
-- Run AFTER sql/ddl/code_dictionary_raw.sql. Non-destructive: adds columns
-- to the existing 999-row table, so a mistake here never costs the pass-1
-- scan of ~356M rows.
-- =====================================================================

ALTER TABLE SYNTHEA_HEALTHCLAIMS.PUBLIC.CODE_DICTIONARY
    ADD COLUMN CODE_CATEGORY VARCHAR(32),
               IS_CLINICAL   BOOLEAN,
               IS_CONDITION  BOOLEAN,
               CLASSIFIED_BY VARCHAR(16);


-- ---------------------------------------------------------------------
-- Step 1: record HOW each row will be decided (independent of the outcome)
-- ---------------------------------------------------------------------
UPDATE SYNTHEA_HEALTHCLAIMS.PUBLIC.CODE_DICTIONARY
SET CLASSIFIED_BY =
    CASE
        WHEN DESCRIPTION IN (
            -- social determinants of health: real, important, but not
            -- conditions being treated
            'Educated to high school level (finding)',
            'Full-time employment (finding)',
            'Has a criminal record (finding)',
            'Homeless (finding)',
            'Housing unsatisfactory (finding)',
            'Lack of access to transportation (finding)',
            'Limited social contact (finding)',
            'Not in labor force (finding)',
            'Only received primary school education (finding)',
            'Part-time employment (finding)',
            'Received certificate of high school equivalency (finding)',
            'Received higher education (finding)',
            'Reports of violence in the environment (finding)',
            'Risk activity involvement (finding)',
            'Served in armed forces (finding)',
            'Serving in military service (finding)',
            'Social isolation (finding)',
            'Social migrant (finding)',
            -- Stress moved here from clinical at the user's direction. It sits
            -- alongside social isolation / limited social contact, which are
            -- already social determinants; treating it as clinical made it the
            -- #6 condition on $1.55B, almost entirely inherited from those
            -- claims via the DIAGNOSIS2 fallback.
            'Stress (finding)',
            'Transport problem (finding)',
            'Unemployed (finding)',
            'Victim of intimate partner abuse (finding)',
            -- administrative events wearing a (finding) tag
            'Died in hospice (finding)',
            'Postoperative visit (finding)',
            'Reasons for treatment delay (finding)',
            'Transition from acute care to home-health care (finding)',
            -- completed deaths: clinical events, but not conditions anyone
            -- bills to treat. Attempted suicide / at-risk codes are NOT here
            -- on purpose -- those patients survived and were treated, so they
            -- are genuine conditions.
            'Sudden Cardiac Death',
            'Death in hospital (event)',
            'Suicide',
            'Suicide - suffocation',
            'Suicide - firearms'
        ) THEN 'manual_override'
        -- only a RECOGNISED tag counts. The regex that fills SEMANTIC_TAG
        -- grabs any trailing "(...)", which can be part of a name rather than
        -- a SNOMED semantic tag -- 'Hib (PRP-OMP)' yields tag 'prp-omp'.
        -- Anything unrecognised must fall through to provenance, not
        -- dead-end in 'Other'.
        WHEN SEMANTIC_TAG IN (
            'disorder', 'finding', 'morphologic abnormality', 'event',
            'procedure', 'regime/therapy', 'situation', 'record artifact',
            'person', 'substance', 'organism', 'physical object',
            'product', 'dose form', 'environment'
        ) THEN 'semantic_tag'
        ELSE 'provenance'
    END;


-- ---------------------------------------------------------------------
-- Step 2: assign the category, honouring that precedence
-- ---------------------------------------------------------------------
UPDATE SYNTHEA_HEALTHCLAIMS.PUBLIC.CODE_DICTIONARY
SET CODE_CATEGORY =
    CASE
        -- (a) hand-reviewed exceptions -----------------------------------
        WHEN CLASSIFIED_BY = 'manual_override' THEN
            CASE
                WHEN DESCRIPTION IN (
                    'Sudden Cardiac Death',
                    'Death in hospital (event)',
                    'Suicide',
                    'Suicide - suffocation',
                    'Suicide - firearms'
                ) THEN 'Mortality event'
                WHEN DESCRIPTION IN (
                    'Died in hospice (finding)',
                    'Postoperative visit (finding)',
                    'Reasons for treatment delay (finding)',
                    'Transition from acute care to home-health care (finding)'
                ) THEN 'Administrative'
                ELSE 'Social determinant'
            END

        -- (b) SNOMED semantic tag ----------------------------------------
        WHEN CLASSIFIED_BY = 'semantic_tag' THEN
            CASE SEMANTIC_TAG
                WHEN 'disorder'                THEN 'Condition'
                WHEN 'finding'                 THEN 'Condition'
                WHEN 'morphologic abnormality' THEN 'Condition'
                -- 'event' served exactly one code, 'Death in hospital (event)',
                -- and got it wrong; that code is now a manual override anyway
                WHEN 'event'                   THEN 'Administrative'
                WHEN 'procedure'               THEN 'Procedure'
                WHEN 'regime/therapy'          THEN 'Procedure'
                WHEN 'situation'               THEN 'Administrative'
                WHEN 'record artifact'         THEN 'Administrative'
                WHEN 'person'                  THEN 'Administrative'
                WHEN 'substance'               THEN 'Substance'
                WHEN 'organism'                THEN 'Substance'
                WHEN 'physical object'         THEN 'Device or supply'
                WHEN 'product'                 THEN 'Medication or vaccine'
                WHEN 'dose form'               THEN 'Medication or vaccine'
                WHEN 'environment'             THEN 'Encounter type'
                ELSE 'Other'
            END

        -- (c) provenance, for the 284 codes with no tag ------------------
        -- Matching is on EXACT list tokens (', NAME, '), because a bare
        -- LIKE '%PROCEDURES%' also matches the substring inside
        -- 'PROCEDURES.REASON' and silently mis-fires.
        --
        -- Precedence: a table that names the thing itself beats a *.REASON
        -- column, which only says the code was cited as a justification.
        -- 'Total knee replacement' is ENCOUNTERS.REASON + PROCEDURES: it is
        -- a procedure that happened to be the reason for a visit, so
        -- PROCEDURES must win. A *.REASON-only code is the fallback -- with
        -- no other evidence, a justification is most likely a diagnosis.
        WHEN ', ' || SOURCE_TABLES || ', ' LIKE '%, CONDITIONS, %'
                                                  THEN 'Condition'
        -- ALLERGIES must come before the .REASON fallback: 'Soy bean' is
        -- (ALLERGIES, ENCOUNTERS.REASON) and is an allergen, not a diagnosis.
        -- Note 'Allergy to substance (finding)' is caught earlier by its
        -- semantic tag and stays a Condition -- being allergic IS a diagnosis,
        -- as distinct from naming the allergen.
        WHEN ', ' || SOURCE_TABLES || ', ' LIKE '%, ALLERGIES, %'
                                                  THEN 'Substance'
        WHEN ', ' || SOURCE_TABLES || ', ' LIKE '%, IMMUNIZATIONS, %'
                                                  THEN 'Medication or vaccine'
        -- MEDICATIONS.CODE is RxNorm drug codes; these turn up in
        -- CLAIMS_TX.PROCEDURECODE as billed drug lines
        WHEN ', ' || SOURCE_TABLES || ', ' LIKE '%, MEDICATIONS, %'
                                                  THEN 'Medication or vaccine'
        WHEN ', ' || SOURCE_TABLES || ', ' LIKE '%, IMAGING_STUDIES, %'
                                                  THEN 'Imaging'
        WHEN ', ' || SOURCE_TABLES || ', ' LIKE '%, DEVICES, %'
                                                  THEN 'Device or supply'
        WHEN ', ' || SOURCE_TABLES || ', ' LIKE '%, SUPPLIES, %'
                                                  THEN 'Device or supply'
        WHEN ', ' || SOURCE_TABLES || ', ' LIKE '%, PROCEDURES, %'
                                                  THEN 'Procedure'
        WHEN ', ' || SOURCE_TABLES || ', ' LIKE '%, ENCOUNTERS, %'
                                                  THEN 'Encounter type'
        WHEN ', ' || SOURCE_TABLES || ', ' LIKE '%, CARE_PLANS, %'
                                                  THEN 'Encounter type'
        WHEN SOURCE_TABLES LIKE '%REASON%'        THEN 'Condition'
        ELSE 'Other'
    END;


-- ---------------------------------------------------------------------
-- Step 3: derive the two boolean flags from the category
-- ---------------------------------------------------------------------
UPDATE SYNTHEA_HEALTHCLAIMS.PUBLIC.CODE_DICTIONARY
SET IS_CONDITION = (CODE_CATEGORY = 'Condition'),
    -- 'Mortality event' is clinical but never a treatable condition
    IS_CLINICAL  = (CODE_CATEGORY IN ('Condition', 'Procedure',
                                      'Medication or vaccine', 'Substance',
                                      'Mortality event', 'Imaging'));
