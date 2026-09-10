-- =====================================================================
-- SYNTHEA_HEALTHCLAIMS.PUBLIC.V_CLAIMS_TX_CLEAN
--
-- Line-grain view over the read-only CLAIMS_TX share, correcting the
-- money, payer and date-window defects documented in DATA_QUALITY_LOG.md.
-- Scope: FROMDATE 2020-01-01..2024-12-31, the single place it is defined
-- (edit the two predicates at the bottom to change it).
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

    -- ---- money: rebuilt from TYPE and METHOD, not raw AMOUNT --------
    IFF(tx.TYPE = 'CHARGE', tx.AMOUNT, 0)                AS BILLED_AMOUNT,
    tx.PAYMENTS                                          AS PAID_AMOUNT,
    IFF(tx.TYPE = 'PAYMENT' AND tx.METHOD =  'ECHECK',
        tx.PAYMENTS, 0)                                  AS PAID_BY_PAYER,
    IFF(tx.TYPE = 'PAYMENT' AND tx.METHOD <> 'ECHECK',
        tx.PAYMENTS, 0)                                  AS PAID_BY_PATIENT,
    tx.TRANSFERS                                         AS TRANSFER_AMOUNT,

    -- ---- renamed so the running-balance trap is unmissable ----------
    tx.OUTSTANDING                                       AS OUTSTANDING_RUNNING_BALANCE,

    -- ---- payer: PAYER_ID keys an insurer-CITY pair, not an insurer -----
    -- group by PAYER_NAME for the insurer, PAYER_CITY for the region.
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
WHERE tx.FROMDATE >= '2020-01-01'        -- standing window: excludes the pre-2020 era and 2019 volume shift
  AND tx.FROMDATE <  '2025-01-01';
