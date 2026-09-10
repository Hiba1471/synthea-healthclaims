-- =====================================================================
-- Q3: which sites are expensive PER PATIENT, and why? Ranking by TOTAL
-- spend tracks simulated city size (9 of the top 10 sit in Cleveland);
-- per-patient cost normalises that away, and decomposing it into billed
-- per encounter x encounters per patient shows the expensive sites are
-- expensive through FREQUENCY, not price. 1,000-patient volume floor;
-- 731 of 3,918 sites clear it.
--
-- GRAIN EXCEPTION: grouped by NAME, not ORGANIZATION_ID, unlike the rest
-- of this project. Several ids share a name, and 13 sites only clear the
-- volume floor once those ids are pooled; grouping by id instead yields
-- 830 rows with 113 duplicated names. Verified against the committed
-- result: 731 rows, zero differences.
-- =====================================================================

WITH base AS (
    SELECT CLAIM_ID, PATIENT_ID, ENCOUNTER_ID, BILLED_AMOUNT
    FROM SYNTHEA_HEALTHCLAIMS.PUBLIC.V_CLAIMS_TX_CLEAN
    WHERE NOT IS_ADMIN_NOISE_CODE
      AND PROCEDURECODE IS NOT NULL
      AND BILLED_AMOUNT > 0
),
by_site AS (
    SELECT
        o.NAME || ' (' || o.CITY || ', ' || o.STATE || ')' AS hospital,
        o.SYNTHEA_CITY                        AS sim_city,
        COUNT(DISTINCT b.PATIENT_ID)          AS patients,
        COUNT(DISTINCT b.ENCOUNTER_ID)        AS encounters,
        SUM(b.BILLED_AMOUNT)                  AS total_billed
    FROM base b
    JOIN SYNTHETIC_HEALTHCARE_DATA_CLINICAL_AND_CLAIMS.SILVER.ENCOUNTERS e
      ON b.ENCOUNTER_ID = e.ENCOUNTER_ID
    JOIN SYNTHETIC_HEALTHCARE_DATA_CLINICAL_AND_CLAIMS.SILVER.ORGANIZATIONS o
      ON e.ORGANIZATION_ID = o.ORGANIZATION_ID
    GROUP BY 1, 2
)
SELECT
    hospital                                              AS "Hospital",
    sim_city                                              AS "Sim City",
    patients                                              AS "Patients",
    ROUND(total_billed)                                   AS "Total Billed",
    ROUND(total_billed / patients)                        AS "Billed per Patient",
    ROUND(total_billed / NULLIF(encounters, 0))           AS "Billed per Encounter",
    ROUND(encounters / patients, 1)                       AS "Encounters per Patient",
    RANK() OVER (ORDER BY total_billed DESC)              AS "Rank by Total",
    RANK() OVER (ORDER BY total_billed / patients DESC)   AS "Rank by Cost per Patient"
FROM by_site
WHERE patients >= 1000
ORDER BY total_billed / patients DESC;
