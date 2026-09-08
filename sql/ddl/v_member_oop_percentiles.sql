-- =====================================================================
-- SYNTHEA_HEALTHCLAIMS.PUBLIC.V_MEMBER_OOP_PERCENTILES
--
-- What a member actually paid out of pocket over the five years, as a
-- distribution rather than an average. One row. Built for Power BI to
-- import, because MEDIAN and MEDIANX are not supported against DirectQuery
-- sources -- if the Power BI table's storage mode is DirectQuery, no DAX
-- rewrite will make a median work, and this is the way round it.
--
-- Expected output, matching sql/results/q2_member_paid_percentiles_2020_2024.csv:
--
--   MEMBERS     MEDIAN   MEAN      P75      P90    PCT_ZERO
--   1,259,375    7,026   16,084   19,005   35,478    0.10
--
-- WHY THE MEDIAN AND NOT THE MEAN. The mean is $16,084, more than double
-- the median $7,026, because the distribution has a long right tail. The
-- mean describes nobody: it is pulled up by a small number of very
-- expensive members. Put the median on the card and the mean in the caption
-- so the skew is visible rather than averaged away.
--
-- THE GRAIN TRAP THIS EXISTS TO AVOID. Taking a median straight off the
-- transaction lines -- MEDIAN(PAID_BY_PATIENT) -- returns 0. A line is
-- either a CHARGE or a PAYMENT, and PAID_BY_PATIENT is zero on every CHARGE
-- row, which is most of them. The median has to be taken over per-member
-- TOTALS, which is what the CTE below builds first.
--
-- Members with zero out-of-pocket are KEPT (0.10% of the population). They
-- are real members who happened to pay nothing, and dropping them would
-- shift every percentile upward.
-- =====================================================================

CREATE OR REPLACE VIEW SYNTHEA_HEALTHCLAIMS.PUBLIC.V_MEMBER_OOP_PERCENTILES AS
WITH member_totals AS (
    -- one row per member: their five-year out-of-pocket total
    SELECT
        PATIENT_ID,
        SUM(PAID_BY_PATIENT) AS oop,
        SUM(BILLED_AMOUNT)   AS billed
    FROM SYNTHEA_HEALTHCLAIMS.PUBLIC.V_CLAIMS_TX_WITH_CARETYPE
    GROUP BY PATIENT_ID
    HAVING SUM(BILLED_AMOUNT) > 0        -- members with no billed care are not a cohort
)
SELECT
    COUNT(*)                                                   AS MEMBERS,
    ROUND(MEDIAN(oop))                                         AS MEDIAN_OOP,
    ROUND(AVG(oop))                                            AS MEAN_OOP,
    ROUND(PERCENTILE_CONT(0.75) WITHIN GROUP (ORDER BY oop))   AS P75_OOP,
    ROUND(PERCENTILE_CONT(0.90) WITHIN GROUP (ORDER BY oop))   AS P90_OOP,
    ROUND(PERCENTILE_CONT(0.95) WITHIN GROUP (ORDER BY oop))   AS P95_OOP,
    ROUND(MAX(oop))                                            AS MAX_OOP,
    ROUND(100.0 * SUM(IFF(oop = 0, 1, 0)) / COUNT(*), 2)       AS PCT_WITH_ZERO_OOP
FROM member_totals;


-- =====================================================================
-- ACCEPTANCE CHECK. Median must be 7,026 and mean 16,084 against
-- sql/results/q2_member_paid_percentiles_2020_2024.csv.
--
-- If MEDIAN_OOP comes back 0, the per-member GROUP BY was skipped somewhere
-- and the median is being taken over transaction lines.
-- =====================================================================
SELECT
    MEMBERS,
    MEDIAN_OOP,
    MEAN_OOP,
    P90_OOP,
    CASE
        WHEN MEDIAN_OOP = 0                     THEN 'FAIL - median taken over lines, not members'
        WHEN MEDIAN_OOP BETWEEN 7000 AND 7050
         AND MEAN_OOP  BETWEEN 16050 AND 16120  THEN 'PASS'
        ELSE 'CHECK - does not match the published figures'
    END                                                        AS ACCEPTANCE
FROM SYNTHEA_HEALTHCLAIMS.PUBLIC.V_MEMBER_OOP_PERCENTILES;
