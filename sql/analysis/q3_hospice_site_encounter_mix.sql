-- =====================================================================
-- Q3 FOLLOW-UP: what actually happens at the hospice-named sites?
--
-- WHY THIS EXISTS. dashboard/two_ways_expensive.html marks 22 sites as
-- "hospices -- one whole stay = one visit", explaining their $2,000-$16,030
-- per-visit figures as a whole multi-week stay counted once. That note was
-- built on delayed_claims_tail_2020_2024.csv, which groups by ENCOUNTERCLASS
-- across every organisation. The chart's cluster is defined by organisation
-- NAME. Those are not the same population, and the note assumed they were.
--
-- q3_site_group_top_conditions.sql exposed the gap: the top conditions at these
-- sites are Normal pregnancy, drug overdose, lacerations, sprains and
-- fractures. That is not end-of-life care, and it should not have been possible
-- under the story the chart was telling.
--
-- WHAT THIS RETURNS. The sites are genuinely hospices and nursing homes -- the
-- names are real, and checked one by one. But their encounters are mixed:
--
--   hospice class    18.1% of visits, 22.3 days each, 50.7% of the money
--   emergency        63.9% of visits,  0.1 days each, 39.3% of the money
--   home             13.1% of visits,  0.0 days,       2.1%
--   snf               2.2% of visits, 19.7 days,       7.2%
--   wellness          2.6% of visits,  0.0 days,       0.7%
--
-- So the long-stay reading holds for the MONEY -- hospice and skilled nursing
-- together are 57.9% of billing at $12,617 and $14,570 a visit across ~20 days
-- -- and that is what lifts the per-visit average. It does NOT hold for the
-- visit COUNT: most visits to these sites are ordinary same-day emergency
-- trips at $2,774, which is an unremarkable price. The pregnancies and
-- fractures are those emergency encounters, not hospice care.
--
-- The per-day rate survives intact: $414,581,221 over 32,859 hospice encounters
-- averaging 22.3 days is about $566 a day, matching the $523-579 quoted from
-- delayed_claims_tail and still among the cheapest care per day in the data.
--
-- Sites matched on NAME; nothing in the data marks a facility as a hospice.
-- Same pattern as q3_site_group_conditions.sql and q3_two_ways_expensive.py.
--
-- Results: sql/results/q3_hospice_site_encounter_mix_2020_2024.csv
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
