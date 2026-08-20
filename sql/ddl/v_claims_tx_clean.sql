-- =====================================================================
-- SYNTHEA_HEALTHCLAIMS.PUBLIC.V_CLAIMS_TX_CLEAN
--
-- Curated line-grain view over the read-only share
-- SYNTHETIC_HEALTHCARE_DATA_CLINICAL_AND_CLAIMS.SILVER.CLAIMS_TX.
-- The share cannot be modified, so the guardrails live here instead.
--
-- Grain: one row per CLAIMS_TX transaction line (unchanged).
-- Scope: FROMDATE 2020-01-01 .. 2024-12-31 (the standing window).
--
-- Data-quality issues neutralised by this view:
--   #1 OUTSTANDING is a MID-FLOW running balance, not terminal A/R.
--      SUM() over it returns $45.3B; true uncollected is $83K.
--      -> exposed only as OUTSTANDING_RUNNING_BALANCE so the name blocks
--         the mistake. For real terminal A/R take the LAST transaction per
--         claim (see sql/snowflake_queries.sql, revenue-cycle section).
--   #2 AMOUNT is populated on TRANSFERIN rows as well as CHARGE rows, so
--      summing it double-counts $23.4B of transferred balances.
--      -> use BILLED_AMOUNT, which is zero off CHARGE rows.
--   #5 encounters.PAYER_ID says who was BILLED, not who PAID.
--      -> PAID_BY_PAYER / PAID_BY_PATIENT split on METHOD
--         (ECHECK = insurer channel; CASH/CHECK/CC/COPAY = patient).
--   #6 Base table spans 1914-2024; unfiltered totals are ~110-year
--      cumulative. -> window baked in below.
--   #7 Volume steps up ~8x at Nov 2019, so calendar-2019 blends two
--      population regimes. -> window starts 2020-01-01, excluding it.
--   #9 PAYERS holds 120 rows = 10 insurers x 12 cities, so PAYER_ID keys an
--      insurer-CITY pair rather than an insurer. This is a grain trap, not
--      corrupt data -- each row carries genuine per-city figures.
--      -> PAYER_NAME collapses to the insurer; PAYER_CITY keeps the regional
--         split available. Both are exposed; neither is lost.
--
-- Deliberately NOT projected (dead or constant in the source):
--   MODIFIER1, MODIFIER2, LINENOTE  (100% null)
--   ADJUSTMENTS (always 0), UNITS (always 1), FEESCHEDULEID (always 1),
--   DIAGNOSISREF1..4 (each a fixed constant)
--
-- NOT baked in on purpose: the PROCEDURECODE = 185347001 noise filter.
-- It is right for procedure-level analysis but wrong for claim-level
-- revenue-cycle work, which needs every line of a claim. Use the
-- IS_ADMIN_NOISE_CODE flag to opt in.
--
-- To change the window, edit the two predicates at the bottom of this file
-- and re-run. That is the single place the standing scope is defined.
-- =====================================================================

CREATE OR REPLACE VIEW SYNTHEA_HEALTHCLAIMS.PUBLIC.V_CLAIMS_TX_CLEAN AS
SELECT
    -- ---- keys -------------------------------------------------------
    tx.CLAIMS_TX_ID,
    tx.CLAIM_ID,
    tx.ENCOUNTER_ID,
    tx.PATIENT_ID,

    -- ---- dates ------------------------------------------------------
    tx.FROMDATE,
    tx.TODATE,
    YEAR(tx.FROMDATE)                                    AS SERVICE_YEAR,

    -- ---- transaction semantics --------------------------------------
    tx.TYPE,                       -- CHARGE / PAYMENT / TRANSFERIN / TRANSFEROUT
    tx.TRANSFERTYPE,               -- '1' primary payer, '2' secondary, 'p' patient
    tx.METHOD,                     -- ECHECK = payer; CASH/CHECK/CC/COPAY = patient
    tx.PROCEDURECODE,
    IFF(tx.PROCEDURECODE = 185347001, TRUE, FALSE)       AS IS_ADMIN_NOISE_CODE,

    -- ---- money (issue #2 and #5) ------------------------------------
    IFF(tx.TYPE = 'CHARGE', tx.AMOUNT, 0)                AS BILLED_AMOUNT,
    tx.PAYMENTS                                          AS PAID_AMOUNT,
    IFF(tx.TYPE = 'PAYMENT' AND tx.METHOD =  'ECHECK',
        tx.PAYMENTS, 0)                                  AS PAID_BY_PAYER,
    IFF(tx.TYPE = 'PAYMENT' AND tx.METHOD <> 'ECHECK',
        tx.PAYMENTS, 0)                                  AS PAID_BY_PATIENT,
    tx.TRANSFERS                                         AS TRANSFER_AMOUNT,

    -- ---- issue #1: renamed so the trap is unmissable ----------------
    tx.OUTSTANDING                                       AS OUTSTANDING_RUNNING_BALANCE,

    -- ---- payer (issue #9) -------------------------------------------
    -- PAYER_ID identifies an insurer-CITY pair, not an insurer: PAYERS holds
    -- 120 rows = 10 insurers x 12 Synthea cities, and each row carries its own
    -- real figures (Cleveland Medicare 128k customers vs Salt Lake City 5.4k).
    -- Nothing is wrong with that -- it is just a grain trap. Group by
    -- PAYER_NAME for "the insurer", or by PAYER_ID / PAYER_CITY to keep the
    -- regional split.
    e.PAYER_ID,
    p.NAME                                               AS PAYER_NAME,
    p.SYNTHEA_CITY                                       AS PAYER_CITY,
    CASE
        WHEN p.NAME IN ('Medicare', 'Medicaid', 'Dual Eligible')
            THEN 'Government'
        WHEN p.NAME = 'NO_INSURANCE'
            THEN 'Self-Pay / Uninsured'
        ELSE 'Commercial'
    END                                                  AS PAYER_TYPE,

    -- ---- encounter context (free from the join we already need) -----
    e.ENCOUNTERCLASS

FROM SYNTHETIC_HEALTHCARE_DATA_CLINICAL_AND_CLAIMS.SILVER.CLAIMS_TX tx
JOIN SYNTHETIC_HEALTHCARE_DATA_CLINICAL_AND_CLAIMS.SILVER.ENCOUNTERS e
    ON tx.ENCOUNTER_ID = e.ENCOUNTER_ID
JOIN SYNTHETIC_HEALTHCARE_DATA_CLINICAL_AND_CLAIMS.SILVER.PAYERS p
    ON e.PAYER_ID = p.PAYER_ID
WHERE tx.FROMDATE >= '2020-01-01'        -- standing window (issues #6, #7)
  AND tx.FROMDATE <  '2025-01-01';
