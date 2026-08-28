-- =====================================================================
-- Q3: which care sites are expensive PER PATIENT, and why?
--
-- Ranking hospitals by TOTAL spend is a trap: it tracks simulated city size,
-- and 9 of the top 10 sit in Cleveland, the most heavily populated simulated
-- city. That is a property of the generator, not a clinical fact.
--
-- Cost PER PATIENT normalises population away and survives the artifact. It
-- also decomposes, which is the point of this query:
--
--     billed per patient  =  billed per encounter  x  encounters per patient
--
-- Emitting both factors separately is what shows that the expensive sites are
-- expensive through FREQUENCY, not price -- the top of the list bills BELOW
-- average per visit and sees the same patients dozens of times.
--
-- Volume floor of 1,000 patients per site. Without it the ranking fills with
-- sites of a handful of patients whose per-patient figure is noise. 731 of
-- 3,918 sites clear it.
--
-- Both rank columns are kept so the gap between them is visible: a site can
-- be 162nd by total spend and 1st by cost per patient.
--
-- GRAIN: sites are grouped by NAME, not by ORGANIZATION_ID. Several ids share
-- a name, and pooling them matters -- 13 sites clear the 1,000-patient floor
-- only once their ids are combined, and grouping by id instead yields 830 rows
-- with 113 duplicated names. Verified against the committed result: 731 rows,
-- 6,579 cells, zero differences.
--
-- Results: sql/results/q3_hospital_cost_intensity_2020_2024.csv
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
