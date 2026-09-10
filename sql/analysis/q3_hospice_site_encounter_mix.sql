-- =====================================================================
-- Q3 follow-up, self-correction: dashboard/two_ways_expensive.html reads
-- 22 hospice-named sites' $2K-$16K per-visit figures as one long stay
-- counted as one visit. q3_top_conditions_by_site_group.sql then showed
-- their top conditions are pregnancy and injuries -- not end-of-life
-- care -- so this checks what actually happens there.
--
-- Result: both readings are partly right. Visits are mostly ordinary
-- same-day ER trips at $2,774 (63.9% of visits, 39.3% of money) -- that
-- is where the pregnancies and fractures are. But hospice + skilled
-- nursing encounters (20.3% of visits, 57.9% of money, ~20 days each)
-- genuinely are long stays, and the per-day rate ($566) still matches
-- the cheap-per-day reading from delayed_claims_tail. The long-stay
-- story holds for the MONEY, not for the visit COUNT.
--
-- Sites matched on NAME; nothing in the data marks a facility as hospice.
-- =====================================================================

WITH sited AS (
    SELECT e.ENCOUNTER_ID, e.ENCOUNTERCLASS,
           DATEDIFF('day', e.ENCOUNTER_START, e.ENCOUNTER_STOP) AS days
    FROM SYNTHETIC_HEALTHCARE_DATA_CLINICAL_AND_CLAIMS.SILVER.ENCOUNTERS e
    JOIN SYNTHETIC_HEALTHCARE_DATA_CLINICAL_AND_CLAIMS.SILVER.ORGANIZATIONS o
      ON e.ORGANIZATION_ID = o.ORGANIZATION_ID
    WHERE (o.NAME ILIKE '%hospice%' OR o.NAME ILIKE '%convalescent%'
        OR o.NAME ILIKE '%palliative%' OR o.NAME ILIKE '%nursing home%'
        OR o.NAME ILIKE '%home care%')
      AND e.ENCOUNTER_START >= '2020-01-01'
      AND e.ENCOUNTER_START <  '2025-01-01'
),
money AS (
    SELECT ENCOUNTER_ID, SUM(BILLED_AMOUNT) AS billed
    FROM SYNTHEA_HEALTHCLAIMS.PUBLIC.V_CLAIMS_TX_CLEAN
    WHERE NOT IS_ADMIN_NOISE_CODE
      AND PROCEDURECODE IS NOT NULL
      AND BILLED_AMOUNT > 0
    GROUP BY ENCOUNTER_ID
)
SELECT
    s.ENCOUNTERCLASS                                      AS "Kind of visit",
    COUNT(*)                                              AS "Visits",
    ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 1)    AS "% of visits",
    ROUND(AVG(s.days), 1)                                 AS "Average days long",
    ROUND(SUM(m.billed))                                  AS "Total billed",
    ROUND(100.0 * SUM(m.billed)
          / SUM(SUM(m.billed)) OVER (), 1)                AS "% of the money",
    ROUND(AVG(m.billed))                                  AS "Billed per visit",
    ROUND(SUM(m.billed) / NULLIF(SUM(s.days), 0))         AS "Billed per day"
FROM sited s
JOIN money m ON s.ENCOUNTER_ID = m.ENCOUNTER_ID
GROUP BY s.ENCOUNTERCLASS
ORDER BY "Total billed" DESC;
