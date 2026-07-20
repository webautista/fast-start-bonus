/*
    Validation script for dbo.FSBTrackings_Load dynamic FSB classification.

    Purpose:
    1. Recalculate expected FSBTrackings rows for a Promotion/Sponsor scope.
    2. Compare expected rows vs dbo.FSBTrackings after dbo.FSBTrackings_Load runs.
    3. Report missing promoters/orders, extra rows, date mismatches, duplicates and rule violations.

    Usage:
    - Set @PromotionID and optional @SponsorID.
    - Run after executing dbo.FSBTrackings_Load.
*/

SET NOCOUNT ON;

DECLARE @PromotionID BIGINT = 1;
DECLARE @SponsorID BIGINT = NULL; -- set a SponsorID to validate a single sponsor

-- Example:
-- SELECT @PromotionID = PromotionID
-- FROM dbo.Promotions
-- WHERE Code = 'FSB_2026_MAIN';

-- TODO: Set this value before running if the SELECT above is not used.
-- SET @PromotionID = 123;

DECLARE @PromotionStartDate DATETIME;
DECLARE @PromotionEndDate DATETIME;
DECLARE @NullDate DATETIME = CONVERT(DATETIME, '19000101', 112);

IF @PromotionID IS NULL
BEGIN
    RAISERROR('Set @PromotionID before running validation.', 16, 1);
    RETURN;
END;

SELECT
    @PromotionStartDate = StartDate,
    @PromotionEndDate = EndDate
FROM dbo.Promotions
WHERE PromotionID = @PromotionID;

IF @PromotionStartDate IS NULL OR @PromotionEndDate IS NULL
BEGIN
    RAISERROR('Invalid @PromotionID.', 16, 1);
    RETURN;
END;

-------------------------------------------------------------------------------
-- Cleanup
-------------------------------------------------------------------------------

IF OBJECT_ID('tempdb..#V_ScopeSponsors') IS NOT NULL DROP TABLE #V_ScopeSponsors;
IF OBJECT_ID('tempdb..#V_BaseOrders') IS NOT NULL DROP TABLE #V_BaseOrders;
IF OBJECT_ID('tempdb..#V_FSB1WindowRows') IS NOT NULL DROP TABLE #V_FSB1WindowRows;
IF OBJECT_ID('tempdb..#V_FSB1Qualified') IS NOT NULL DROP TABLE #V_FSB1Qualified;
IF OBJECT_ID('tempdb..#V_FSB1NormalRows') IS NOT NULL DROP TABLE #V_FSB1NormalRows;
IF OBJECT_ID('tempdb..#V_FSB1ExtWindowRows') IS NOT NULL DROP TABLE #V_FSB1ExtWindowRows;
IF OBJECT_ID('tempdb..#V_FSB1ExtQualified') IS NOT NULL DROP TABLE #V_FSB1ExtQualified;
IF OBJECT_ID('tempdb..#V_FSB1ExtRows') IS NOT NULL DROP TABLE #V_FSB1ExtRows;
IF OBJECT_ID('tempdb..#V_FSB1Completion') IS NOT NULL DROP TABLE #V_FSB1Completion;
IF OBJECT_ID('tempdb..#V_FSB2WindowRows') IS NOT NULL DROP TABLE #V_FSB2WindowRows;
IF OBJECT_ID('tempdb..#V_FSB2Qualified') IS NOT NULL DROP TABLE #V_FSB2Qualified;
IF OBJECT_ID('tempdb..#V_FSB2Rows') IS NOT NULL DROP TABLE #V_FSB2Rows;
IF OBJECT_ID('tempdb..#V_FSB3WindowRows') IS NOT NULL DROP TABLE #V_FSB3WindowRows;
IF OBJECT_ID('tempdb..#V_FSB3Qualified') IS NOT NULL DROP TABLE #V_FSB3Qualified;
IF OBJECT_ID('tempdb..#V_FSB3Rows') IS NOT NULL DROP TABLE #V_FSB3Rows;
IF OBJECT_ID('tempdb..#V_Expected') IS NOT NULL DROP TABLE #V_Expected;
IF OBJECT_ID('tempdb..#V_Actual') IS NOT NULL DROP TABLE #V_Actual;

-------------------------------------------------------------------------------
-- 1. Scope sponsors
-------------------------------------------------------------------------------

CREATE TABLE #V_ScopeSponsors
(
    PromotionID BIGINT NOT NULL,
    SponsorID BIGINT NOT NULL,
    SponsorFSB1Start DATETIME NOT NULL
);

INSERT INTO #V_ScopeSponsors
(
    PromotionID,
    SponsorID,
    SponsorFSB1Start
)
SELECT DISTINCT
    @PromotionID AS PromotionID,
    sponsor.PromoterID AS SponsorID,
    sponsor.FSB1StartDate AS SponsorFSB1Start
FROM dbo.Promoters sponsor
WHERE sponsor.FSB1StartDate IS NOT NULL
  AND sponsor.FSB1EndDate IS NOT NULL
  AND (@SponsorID IS NULL OR sponsor.PromoterID = @SponsorID);

CREATE UNIQUE CLUSTERED INDEX CX_V_ScopeSponsors
ON #V_ScopeSponsors
(
    PromotionID,
    SponsorID,
    SponsorFSB1Start
);

-------------------------------------------------------------------------------
-- 2. Base valid orders: one valid order per promoter in the FSB cycle.
-------------------------------------------------------------------------------

CREATE TABLE #V_BaseOrders
(
    PromotionID BIGINT NOT NULL,
    SponsorID BIGINT NOT NULL,
    PromoterID BIGINT NOT NULL,
    OrderID BIGINT NOT NULL,
    OrderDate DATETIME NOT NULL,

    SponsorFSB1Start DATETIME NOT NULL,
    SponsorFSB1MaxEnd DATETIME NOT NULL,
    SponsorFSB1ExtMaxEnd DATETIME NOT NULL
);

;WITH RawOrders AS
(
    SELECT
        @PromotionID AS PromotionID,

        sponsor.PromoterID AS SponsorID,
        child.PromoterID AS PromoterID,

        o.OrderID,
        o.OrderDate,

        scope.SponsorFSB1Start AS SponsorFSB1Start,
        DATEADD(DAY, 7, scope.SponsorFSB1Start) AS SponsorFSB1MaxEnd,
        DATEADD(DAY, 14, scope.SponsorFSB1Start) AS SponsorFSB1ExtMaxEnd,

        ROW_NUMBER() OVER
        (
            PARTITION BY
                sponsor.PromoterID,
                child.PromoterID,
                scope.SponsorFSB1Start
            ORDER BY
                o.OrderDate,
                o.OrderID
        ) AS rn
    FROM dbo.Promoters child
    INNER JOIN dbo.Promoters sponsor
        ON sponsor.PromoterID = child.SponsorID
    INNER JOIN #V_ScopeSponsors scope
        ON scope.PromotionID = @PromotionID
       AND scope.SponsorID = sponsor.PromoterID
       AND scope.SponsorFSB1Start = sponsor.FSB1StartDate
    INNER JOIN dbo.UserProfile upChild
        ON upChild.UserID = child.UserProfileID
    INNER JOIN dbo.MWRCustomers c
        ON c.UserID = upChild.UserID
    INNER JOIN dbo.[Order] o
        ON o.CustomerID = c.CustomerID
    LEFT JOIN dbo.PromotionProducts ppExcluded
        ON ppExcluded.PromotionID = @PromotionID
       AND ppExcluded.ProductID = o.ProductID
       AND ppExcluded.IsExcluded = 1
    WHERE ppExcluded.PromotionProductID IS NULL
      AND o.Status = 'Active'
      AND o.OrderDate IS NOT NULL
      AND o.OrderDate >= @PromotionStartDate
      AND o.OrderDate <= @PromotionEndDate
      AND o.OrderDate >= scope.SponsorFSB1Start
      AND o.OrderDate <= DATEADD(DAY, 21, scope.SponsorFSB1Start)
)
INSERT INTO #V_BaseOrders
(
    PromotionID,
    SponsorID,
    PromoterID,
    OrderID,
    OrderDate,
    SponsorFSB1Start,
    SponsorFSB1MaxEnd,
    SponsorFSB1ExtMaxEnd
)
SELECT
    PromotionID,
    SponsorID,
    PromoterID,
    OrderID,
    OrderDate,
    SponsorFSB1Start,
    SponsorFSB1MaxEnd,
    SponsorFSB1ExtMaxEnd
FROM RawOrders
WHERE rn = 1
OPTION (RECOMPILE);

CREATE CLUSTERED INDEX CX_V_BaseOrders
ON #V_BaseOrders
(
    PromotionID,
    SponsorID,
    SponsorFSB1Start,
    PromoterID
);

CREATE INDEX IX_V_BaseOrders_OrderCursor
ON #V_BaseOrders
(
    SponsorID,
    SponsorFSB1Start,
    OrderDate,
    OrderID
);

-------------------------------------------------------------------------------
-- 3. Expected FSB1 normal
-------------------------------------------------------------------------------

;WITH RankedFSB1 AS
(
    SELECT
        b.*,
        ROW_NUMBER() OVER
        (
            PARTITION BY
                b.PromotionID,
                b.SponsorID,
                b.SponsorFSB1Start
            ORDER BY
                b.OrderDate,
                b.OrderID
        ) AS FSB1Rank
    FROM #V_BaseOrders b
    WHERE b.OrderDate >= b.SponsorFSB1Start
      AND b.OrderDate <= b.SponsorFSB1MaxEnd
)
SELECT *
INTO #V_FSB1WindowRows
FROM RankedFSB1;

CREATE CLUSTERED INDEX CX_V_FSB1WindowRows
ON #V_FSB1WindowRows
(
    PromotionID,
    SponsorID,
    SponsorFSB1Start,
    FSB1Rank,
    PromoterID
);

SELECT
    PromotionID,
    SponsorID,
    SponsorFSB1Start,
    OrderDate AS FSB1EndDate,
    OrderID AS FSB1EndOrderID,
    OrderDate AS FSB2StartDate,
    SponsorFSB1ExtMaxEnd AS SponsorFSB1ExtEnd
INTO #V_FSB1Qualified
FROM #V_FSB1WindowRows
WHERE FSB1Rank = 2;

CREATE UNIQUE CLUSTERED INDEX CX_V_FSB1Qualified
ON #V_FSB1Qualified
(
    PromotionID,
    SponsorID,
    SponsorFSB1Start
);

SELECT f1.*
INTO #V_FSB1NormalRows
FROM #V_FSB1WindowRows f1
INNER JOIN #V_FSB1Qualified q
    ON q.PromotionID = f1.PromotionID
   AND q.SponsorID = f1.SponsorID
   AND q.SponsorFSB1Start = f1.SponsorFSB1Start
WHERE f1.FSB1Rank <= 2;

CREATE CLUSTERED INDEX CX_V_FSB1NormalRows
ON #V_FSB1NormalRows
(
    PromotionID,
    SponsorID,
    SponsorFSB1Start,
    PromoterID
);

-------------------------------------------------------------------------------
-- 4. Expected FSB1_EXT. Only when normal FSB1 was not completed.
--    FSB1_EXT does not unlock FSB2 or FSB3.
-------------------------------------------------------------------------------

;WITH RankedFSB1Ext AS
(
    SELECT
        b.*,
        ROW_NUMBER() OVER
        (
            PARTITION BY
                b.PromotionID,
                b.SponsorID,
                b.SponsorFSB1Start
            ORDER BY
                b.OrderDate,
                b.OrderID
        ) AS FSB1ExtRank
    FROM #V_BaseOrders b
    WHERE b.OrderDate >= b.SponsorFSB1Start
      AND b.OrderDate <= b.SponsorFSB1ExtMaxEnd
      AND NOT EXISTS
      (
          SELECT 1
          FROM #V_FSB1Qualified q
          WHERE q.PromotionID = b.PromotionID
            AND q.SponsorID = b.SponsorID
            AND q.SponsorFSB1Start = b.SponsorFSB1Start
      )
)
SELECT *
INTO #V_FSB1ExtWindowRows
FROM RankedFSB1Ext;

CREATE CLUSTERED INDEX CX_V_FSB1ExtWindowRows
ON #V_FSB1ExtWindowRows
(
    PromotionID,
    SponsorID,
    SponsorFSB1Start,
    FSB1ExtRank,
    PromoterID
);

SELECT
    PromotionID,
    SponsorID,
    SponsorFSB1Start,
    OrderDate AS FSB1EndDate,
    OrderID AS FSB1EndOrderID,
    OrderDate AS FSB2StartDate,
    SponsorFSB1ExtMaxEnd AS SponsorFSB1ExtEnd
INTO #V_FSB1ExtQualified
FROM #V_FSB1ExtWindowRows
WHERE FSB1ExtRank = 2;

CREATE UNIQUE CLUSTERED INDEX CX_V_FSB1ExtQualified
ON #V_FSB1ExtQualified
(
    PromotionID,
    SponsorID,
    SponsorFSB1Start
);

SELECT ext.*
INTO #V_FSB1ExtRows
FROM #V_FSB1ExtWindowRows ext
INNER JOIN #V_FSB1ExtQualified q
    ON q.PromotionID = ext.PromotionID
   AND q.SponsorID = ext.SponsorID
   AND q.SponsorFSB1Start = ext.SponsorFSB1Start
WHERE ext.FSB1ExtRank <= 2;

CREATE CLUSTERED INDEX CX_V_FSB1ExtRows
ON #V_FSB1ExtRows
(
    PromotionID,
    SponsorID,
    SponsorFSB1Start,
    PromoterID
);

-------------------------------------------------------------------------------
-- 5. Expected FSB2. Only after regular FSB1.
-------------------------------------------------------------------------------

SELECT
    q.PromotionID,
    q.SponsorID,
    q.SponsorFSB1Start,
    CAST('FSB1' AS VARCHAR(20)) AS FSB1CompletionType,
    q.FSB1EndDate,
    q.FSB1EndOrderID,
    q.FSB2StartDate,
    q.SponsorFSB1ExtEnd
INTO #V_FSB1Completion
FROM #V_FSB1Qualified q;

CREATE UNIQUE CLUSTERED INDEX CX_V_FSB1Completion
ON #V_FSB1Completion
(
    PromotionID,
    SponsorID,
    SponsorFSB1Start
);

;WITH RankedFSB2 AS
(
    SELECT
        b.*,
        f1.FSB1EndDate,
        f1.FSB1EndOrderID,
        f1.FSB2StartDate,
        f1.SponsorFSB1ExtEnd,
        ROW_NUMBER() OVER
        (
            PARTITION BY
                b.PromotionID,
                b.SponsorID,
                b.SponsorFSB1Start
            ORDER BY
                b.OrderDate,
                b.OrderID
        ) AS FSB2Rank
    FROM #V_BaseOrders b
    INNER JOIN #V_FSB1Completion f1
        ON f1.PromotionID = b.PromotionID
       AND f1.SponsorID = b.SponsorID
       AND f1.SponsorFSB1Start = b.SponsorFSB1Start
    WHERE
      (
             b.OrderDate > f1.FSB1EndDate
          OR (b.OrderDate = f1.FSB1EndDate AND b.OrderID > f1.FSB1EndOrderID)
      )
      AND b.OrderDate <= DATEADD(DAY, 7, f1.FSB2StartDate)
      AND NOT EXISTS
      (
          SELECT 1
          FROM #V_FSB1NormalRows f1Rows
          WHERE f1Rows.PromotionID = b.PromotionID
            AND f1Rows.SponsorID = b.SponsorID
            AND f1Rows.SponsorFSB1Start = b.SponsorFSB1Start
            AND f1Rows.PromoterID = b.PromoterID
      )
      AND NOT EXISTS
      (
          SELECT 1
          FROM #V_FSB1ExtRows extRows
          WHERE extRows.PromotionID = b.PromotionID
            AND extRows.SponsorID = b.SponsorID
            AND extRows.SponsorFSB1Start = b.SponsorFSB1Start
            AND extRows.PromoterID = b.PromoterID
      )
)
SELECT *
INTO #V_FSB2WindowRows
FROM RankedFSB2;

CREATE CLUSTERED INDEX CX_V_FSB2WindowRows
ON #V_FSB2WindowRows
(
    PromotionID,
    SponsorID,
    SponsorFSB1Start,
    FSB2Rank,
    PromoterID
);

SELECT
    PromotionID,
    SponsorID,
    SponsorFSB1Start,
    FSB2StartDate,
    OrderDate AS FSB2EndDate,
    OrderID AS FSB2EndOrderID,
    OrderDate AS FSB3StartDate
INTO #V_FSB2Qualified
FROM #V_FSB2WindowRows
WHERE FSB2Rank = 2;

CREATE UNIQUE CLUSTERED INDEX CX_V_FSB2Qualified
ON #V_FSB2Qualified
(
    PromotionID,
    SponsorID,
    SponsorFSB1Start
);

SELECT f2.*
INTO #V_FSB2Rows
FROM #V_FSB2WindowRows f2
INNER JOIN #V_FSB2Qualified q
    ON q.PromotionID = f2.PromotionID
   AND q.SponsorID = f2.SponsorID
   AND q.SponsorFSB1Start = f2.SponsorFSB1Start
WHERE f2.FSB2Rank <= 2;

CREATE CLUSTERED INDEX CX_V_FSB2Rows
ON #V_FSB2Rows
(
    PromotionID,
    SponsorID,
    SponsorFSB1Start,
    PromoterID
);

-------------------------------------------------------------------------------
-- 6. Expected FSB3. Only after regular FSB1 and FSB2.
-------------------------------------------------------------------------------

;WITH RankedFSB3 AS
(
    SELECT
        b.*,
        f2.FSB2StartDate,
        f2.FSB2EndDate,
        f2.FSB2EndOrderID,
        f2.FSB3StartDate,
        ROW_NUMBER() OVER
        (
            PARTITION BY
                b.PromotionID,
                b.SponsorID,
                b.SponsorFSB1Start
            ORDER BY
                b.OrderDate,
                b.OrderID
        ) AS FSB3Rank
    FROM #V_BaseOrders b
    INNER JOIN #V_FSB2Qualified f2
        ON f2.PromotionID = b.PromotionID
       AND f2.SponsorID = b.SponsorID
       AND f2.SponsorFSB1Start = b.SponsorFSB1Start
    WHERE
      (
             b.OrderDate > f2.FSB2EndDate
          OR (b.OrderDate = f2.FSB2EndDate AND b.OrderID > f2.FSB2EndOrderID)
      )
      AND b.OrderDate <= DATEADD(DAY, 7, f2.FSB3StartDate)
      AND NOT EXISTS
      (
          SELECT 1
          FROM #V_FSB1NormalRows f1Rows
          WHERE f1Rows.PromotionID = b.PromotionID
            AND f1Rows.SponsorID = b.SponsorID
            AND f1Rows.SponsorFSB1Start = b.SponsorFSB1Start
            AND f1Rows.PromoterID = b.PromoterID
      )
      AND NOT EXISTS
      (
          SELECT 1
          FROM #V_FSB1ExtRows extRows
          WHERE extRows.PromotionID = b.PromotionID
            AND extRows.SponsorID = b.SponsorID
            AND extRows.SponsorFSB1Start = b.SponsorFSB1Start
            AND extRows.PromoterID = b.PromoterID
      )
      AND NOT EXISTS
      (
          SELECT 1
          FROM #V_FSB2Rows f2Rows
          WHERE f2Rows.PromotionID = b.PromotionID
            AND f2Rows.SponsorID = b.SponsorID
            AND f2Rows.SponsorFSB1Start = b.SponsorFSB1Start
            AND f2Rows.PromoterID = b.PromoterID
      )
)
SELECT *
INTO #V_FSB3WindowRows
FROM RankedFSB3;

CREATE CLUSTERED INDEX CX_V_FSB3WindowRows
ON #V_FSB3WindowRows
(
    PromotionID,
    SponsorID,
    SponsorFSB1Start,
    FSB3Rank,
    PromoterID
);

SELECT
    PromotionID,
    SponsorID,
    SponsorFSB1Start,
    FSB3StartDate,
    OrderDate AS FSB3EndDate
INTO #V_FSB3Qualified
FROM #V_FSB3WindowRows
WHERE FSB3Rank = 2;

CREATE UNIQUE CLUSTERED INDEX CX_V_FSB3Qualified
ON #V_FSB3Qualified
(
    PromotionID,
    SponsorID,
    SponsorFSB1Start
);

SELECT f3.*
INTO #V_FSB3Rows
FROM #V_FSB3WindowRows f3
INNER JOIN #V_FSB3Qualified q
    ON q.PromotionID = f3.PromotionID
   AND q.SponsorID = f3.SponsorID
   AND q.SponsorFSB1Start = f3.SponsorFSB1Start
WHERE f3.FSB3Rank <= 2;

CREATE CLUSTERED INDEX CX_V_FSB3Rows
ON #V_FSB3Rows
(
    PromotionID,
    SponsorID,
    SponsorFSB1Start,
    PromoterID
);

-------------------------------------------------------------------------------
-- 7. Expected classified rows
-------------------------------------------------------------------------------

CREATE TABLE #V_Expected
(
    PromotionID BIGINT NOT NULL,
    SponsorID BIGINT NOT NULL,
    PromoterID BIGINT NOT NULL,
    OrderID BIGINT NOT NULL,
    OrderDate DATETIME NOT NULL,
    FSBType VARCHAR(20) NOT NULL,

    SponsorFSB1Start DATETIME NOT NULL,
    SponsorFSB1End DATETIME NOT NULL,
    SponsorFSB1ExtEnd DATETIME NOT NULL,

    SponsorFSB2Start DATETIME NULL,
    SponsorFSB2End DATETIME NULL,

    SponsorFSB3Start DATETIME NULL,
    SponsorFSB3End DATETIME NULL
);

INSERT INTO #V_Expected
SELECT
    f1Rows.PromotionID,
    f1Rows.SponsorID,
    f1Rows.PromoterID,
    f1Rows.OrderID,
    f1Rows.OrderDate,
    'FSB1' AS FSBType,
    f1Rows.SponsorFSB1Start,
    f1.FSB1EndDate AS SponsorFSB1End,
    f1.SponsorFSB1ExtEnd AS SponsorFSB1ExtEnd,
    f1.FSB2StartDate AS SponsorFSB2Start,
    f2.FSB2EndDate AS SponsorFSB2End,
    f2.FSB3StartDate AS SponsorFSB3Start,
    f3.FSB3EndDate AS SponsorFSB3End
FROM #V_FSB1NormalRows f1Rows
INNER JOIN #V_FSB1Completion f1
    ON f1.PromotionID = f1Rows.PromotionID
   AND f1.SponsorID = f1Rows.SponsorID
   AND f1.SponsorFSB1Start = f1Rows.SponsorFSB1Start
   AND f1.FSB1CompletionType = 'FSB1'
LEFT JOIN #V_FSB2Qualified f2
    ON f2.PromotionID = f1Rows.PromotionID
   AND f2.SponsorID = f1Rows.SponsorID
   AND f2.SponsorFSB1Start = f1Rows.SponsorFSB1Start
LEFT JOIN #V_FSB3Qualified f3
    ON f3.PromotionID = f1Rows.PromotionID
   AND f3.SponsorID = f1Rows.SponsorID
   AND f3.SponsorFSB1Start = f1Rows.SponsorFSB1Start;

INSERT INTO #V_Expected
SELECT
    extRows.PromotionID,
    extRows.SponsorID,
    extRows.PromoterID,
    extRows.OrderID,
    extRows.OrderDate,
    'FSB1_EXT' AS FSBType,
    extRows.SponsorFSB1Start,
    f1Ext.FSB1EndDate AS SponsorFSB1End,
    f1Ext.SponsorFSB1ExtEnd AS SponsorFSB1ExtEnd,
    NULL AS SponsorFSB2Start,
    NULL AS SponsorFSB2End,
    NULL AS SponsorFSB3Start,
    NULL AS SponsorFSB3End
FROM #V_FSB1ExtRows extRows
INNER JOIN #V_FSB1ExtQualified f1Ext
    ON f1Ext.PromotionID = extRows.PromotionID
   AND f1Ext.SponsorID = extRows.SponsorID
   AND f1Ext.SponsorFSB1Start = extRows.SponsorFSB1Start;

INSERT INTO #V_Expected
SELECT
    f2Rows.PromotionID,
    f2Rows.SponsorID,
    f2Rows.PromoterID,
    f2Rows.OrderID,
    f2Rows.OrderDate,
    'FSB2' AS FSBType,
    f2Rows.SponsorFSB1Start,
    f1.FSB1EndDate AS SponsorFSB1End,
    f1.SponsorFSB1ExtEnd AS SponsorFSB1ExtEnd,
    f1.FSB2StartDate AS SponsorFSB2Start,
    f2.FSB2EndDate AS SponsorFSB2End,
    f2.FSB3StartDate AS SponsorFSB3Start,
    f3.FSB3EndDate AS SponsorFSB3End
FROM #V_FSB2Rows f2Rows
INNER JOIN #V_FSB1Completion f1
    ON f1.PromotionID = f2Rows.PromotionID
   AND f1.SponsorID = f2Rows.SponsorID
   AND f1.SponsorFSB1Start = f2Rows.SponsorFSB1Start
INNER JOIN #V_FSB2Qualified f2
    ON f2.PromotionID = f2Rows.PromotionID
   AND f2.SponsorID = f2Rows.SponsorID
   AND f2.SponsorFSB1Start = f2Rows.SponsorFSB1Start
LEFT JOIN #V_FSB3Qualified f3
    ON f3.PromotionID = f2Rows.PromotionID
   AND f3.SponsorID = f2Rows.SponsorID
   AND f3.SponsorFSB1Start = f2Rows.SponsorFSB1Start;

INSERT INTO #V_Expected
SELECT
    f3Rows.PromotionID,
    f3Rows.SponsorID,
    f3Rows.PromoterID,
    f3Rows.OrderID,
    f3Rows.OrderDate,
    'FSB3' AS FSBType,
    f3Rows.SponsorFSB1Start,
    f1.FSB1EndDate AS SponsorFSB1End,
    f1.SponsorFSB1ExtEnd AS SponsorFSB1ExtEnd,
    f1.FSB2StartDate AS SponsorFSB2Start,
    f2.FSB2EndDate AS SponsorFSB2End,
    f2.FSB3StartDate AS SponsorFSB3Start,
    f3.FSB3EndDate AS SponsorFSB3End
FROM #V_FSB3Rows f3Rows
INNER JOIN #V_FSB1Completion f1
    ON f1.PromotionID = f3Rows.PromotionID
   AND f1.SponsorID = f3Rows.SponsorID
   AND f1.SponsorFSB1Start = f3Rows.SponsorFSB1Start
INNER JOIN #V_FSB2Qualified f2
    ON f2.PromotionID = f3Rows.PromotionID
   AND f2.SponsorID = f3Rows.SponsorID
   AND f2.SponsorFSB1Start = f3Rows.SponsorFSB1Start
INNER JOIN #V_FSB3Qualified f3
    ON f3.PromotionID = f3Rows.PromotionID
   AND f3.SponsorID = f3Rows.SponsorID
   AND f3.SponsorFSB1Start = f3Rows.SponsorFSB1Start;

CREATE CLUSTERED INDEX CX_V_Expected
ON #V_Expected
(
    PromotionID,
    SponsorID,
    SponsorFSB1Start,
    FSBType,
    PromoterID,
    OrderID
);

-------------------------------------------------------------------------------
-- 8. Actual current FSBTrackings rows in the same scope
-------------------------------------------------------------------------------

SELECT
    ft.PromotionID,
    ft.SponsorID,
    ft.PromoterID,
    ft.OrderID,
    o.OrderDate,
    ft.FSBType,

    ft.SponsorFSB1Start,
    ft.SponsorFSB1End,
    ft.SponsorFSB1ExtEnd,

    ft.SponsorFSB2Start,
    ft.SponsorFSB2End,

    ft.SponsorFSB3Start,
    ft.SponsorFSB3End
INTO #V_Actual
FROM dbo.FSBTrackings ft
INNER JOIN #V_ScopeSponsors scope
    ON scope.PromotionID = ft.PromotionID
   AND scope.SponsorID = ft.SponsorID
   AND scope.SponsorFSB1Start = ft.SponsorFSB1Start
LEFT JOIN dbo.[Order] o
    ON o.OrderID = ft.OrderID
WHERE ft.PromotionID = @PromotionID
  AND (@SponsorID IS NULL OR ft.SponsorID = @SponsorID);

CREATE CLUSTERED INDEX CX_V_Actual
ON #V_Actual
(
    PromotionID,
    SponsorID,
    SponsorFSB1Start,
    FSBType,
    PromoterID,
    OrderID
);

-------------------------------------------------------------------------------
-- 9. Summary result. PASS when MissingRows, ExtraRows and DateMismatchRows are 0.
-------------------------------------------------------------------------------

;WITH Missing AS
(
    SELECT e.*
    FROM #V_Expected e
    LEFT JOIN #V_Actual a
        ON a.PromotionID = e.PromotionID
       AND a.SponsorID = e.SponsorID
       AND a.PromoterID = e.PromoterID
       AND a.OrderID = e.OrderID
       AND a.FSBType = e.FSBType
       AND a.SponsorFSB1Start = e.SponsorFSB1Start
    WHERE a.OrderID IS NULL
),
Extra AS
(
    SELECT a.*
    FROM #V_Actual a
    LEFT JOIN #V_Expected e
        ON e.PromotionID = a.PromotionID
       AND e.SponsorID = a.SponsorID
       AND e.PromoterID = a.PromoterID
       AND e.OrderID = a.OrderID
       AND e.FSBType = a.FSBType
       AND e.SponsorFSB1Start = a.SponsorFSB1Start
    WHERE e.OrderID IS NULL
),
DateMismatch AS
(
    SELECT e.*
    FROM #V_Expected e
    INNER JOIN #V_Actual a
        ON a.PromotionID = e.PromotionID
       AND a.SponsorID = e.SponsorID
       AND a.PromoterID = e.PromoterID
       AND a.OrderID = e.OrderID
       AND a.FSBType = e.FSBType
       AND a.SponsorFSB1Start = e.SponsorFSB1Start
    WHERE ISNULL(a.SponsorFSB1End, @NullDate) <> ISNULL(e.SponsorFSB1End, @NullDate)
       OR ISNULL(a.SponsorFSB1ExtEnd, @NullDate) <> ISNULL(e.SponsorFSB1ExtEnd, @NullDate)
       OR ISNULL(a.SponsorFSB2Start, @NullDate) <> ISNULL(e.SponsorFSB2Start, @NullDate)
       OR ISNULL(a.SponsorFSB2End, @NullDate) <> ISNULL(e.SponsorFSB2End, @NullDate)
       OR ISNULL(a.SponsorFSB3Start, @NullDate) <> ISNULL(e.SponsorFSB3Start, @NullDate)
       OR ISNULL(a.SponsorFSB3End, @NullDate) <> ISNULL(e.SponsorFSB3End, @NullDate)
)
SELECT
    CASE
        WHEN (SELECT COUNT(*) FROM Missing) = 0
         AND (SELECT COUNT(*) FROM Extra) = 0
         AND (SELECT COUNT(*) FROM DateMismatch) = 0
        THEN 'PASS'
        ELSE 'FAIL'
    END AS ValidationStatus,
    (SELECT COUNT(*) FROM #V_ScopeSponsors) AS ScopeSponsors,
    (SELECT COUNT(*) FROM #V_BaseOrders) AS BaseValidOrders,
    (SELECT COUNT(*) FROM #V_Expected) AS ExpectedTrackingRows,
    (SELECT COUNT(*) FROM #V_Actual) AS ActualTrackingRows,
    (SELECT COUNT(*) FROM Missing) AS MissingRows,
    (SELECT COUNT(*) FROM Extra) AS ExtraRows,
    (SELECT COUNT(*) FROM DateMismatch) AS DateMismatchRows;

-------------------------------------------------------------------------------
-- 10. Detail: expected rows that were not loaded to dbo.FSBTrackings.
--     This is the primary report to find sponsors/promoters left out.
-------------------------------------------------------------------------------

SELECT
    'MISSING_IN_FSBTRACKINGS' AS Issue,
    e.*
FROM #V_Expected e
LEFT JOIN #V_Actual a
    ON a.PromotionID = e.PromotionID
   AND a.SponsorID = e.SponsorID
   AND a.PromoterID = e.PromoterID
   AND a.OrderID = e.OrderID
   AND a.FSBType = e.FSBType
   AND a.SponsorFSB1Start = e.SponsorFSB1Start
WHERE a.OrderID IS NULL
ORDER BY
    e.SponsorID,
    e.SponsorFSB1Start,
    CASE e.FSBType
        WHEN 'FSB1' THEN 1
        WHEN 'FSB1_EXT' THEN 2
        WHEN 'FSB2' THEN 3
        WHEN 'FSB3' THEN 4
        ELSE 99
    END,
    e.OrderDate,
    e.OrderID;

-------------------------------------------------------------------------------
-- 11. Detail: sponsors that have expected rows but no actual tracking rows at all.
-------------------------------------------------------------------------------

SELECT
    'SPONSOR_WITH_EXPECTED_ROWS_BUT_ZERO_TRACKING' AS Issue,
    e.PromotionID,
    e.SponsorID,
    e.SponsorFSB1Start,
    COUNT(*) AS ExpectedRows
FROM #V_Expected e
LEFT JOIN
(
    SELECT DISTINCT
        PromotionID,
        SponsorID,
        SponsorFSB1Start
    FROM #V_Actual
) a
    ON a.PromotionID = e.PromotionID
   AND a.SponsorID = e.SponsorID
   AND a.SponsorFSB1Start = e.SponsorFSB1Start
WHERE a.SponsorID IS NULL
GROUP BY
    e.PromotionID,
    e.SponsorID,
    e.SponsorFSB1Start
ORDER BY
    e.SponsorID,
    e.SponsorFSB1Start;

-------------------------------------------------------------------------------
-- 12. Detail: rows present in dbo.FSBTrackings that are not expected.
-------------------------------------------------------------------------------

SELECT
    'EXTRA_IN_FSBTRACKINGS' AS Issue,
    a.*
FROM #V_Actual a
LEFT JOIN #V_Expected e
    ON e.PromotionID = a.PromotionID
   AND e.SponsorID = a.SponsorID
   AND e.PromoterID = a.PromoterID
   AND e.OrderID = a.OrderID
   AND e.FSBType = a.FSBType
   AND e.SponsorFSB1Start = a.SponsorFSB1Start
WHERE e.OrderID IS NULL
ORDER BY
    a.SponsorID,
    a.SponsorFSB1Start,
    CASE a.FSBType
        WHEN 'FSB1' THEN 1
        WHEN 'FSB1_EXT' THEN 2
        WHEN 'FSB2' THEN 3
        WHEN 'FSB3' THEN 4
        ELSE 99
    END,
    a.OrderDate,
    a.OrderID;

-------------------------------------------------------------------------------
-- 13. Detail: same key exists but window dates are different.
-------------------------------------------------------------------------------

SELECT
    'DATE_MISMATCH' AS Issue,
    e.PromotionID,
    e.SponsorID,
    e.PromoterID,
    e.OrderID,
    e.FSBType,
    e.SponsorFSB1Start,
    e.SponsorFSB1End AS ExpectedSponsorFSB1End,
    a.SponsorFSB1End AS ActualSponsorFSB1End,
    e.SponsorFSB1ExtEnd AS ExpectedSponsorFSB1ExtEnd,
    a.SponsorFSB1ExtEnd AS ActualSponsorFSB1ExtEnd,
    e.SponsorFSB2Start AS ExpectedSponsorFSB2Start,
    a.SponsorFSB2Start AS ActualSponsorFSB2Start,
    e.SponsorFSB2End AS ExpectedSponsorFSB2End,
    a.SponsorFSB2End AS ActualSponsorFSB2End,
    e.SponsorFSB3Start AS ExpectedSponsorFSB3Start,
    a.SponsorFSB3Start AS ActualSponsorFSB3Start,
    e.SponsorFSB3End AS ExpectedSponsorFSB3End,
    a.SponsorFSB3End AS ActualSponsorFSB3End
FROM #V_Expected e
INNER JOIN #V_Actual a
    ON a.PromotionID = e.PromotionID
   AND a.SponsorID = e.SponsorID
   AND a.PromoterID = e.PromoterID
   AND a.OrderID = e.OrderID
   AND a.FSBType = e.FSBType
   AND a.SponsorFSB1Start = e.SponsorFSB1Start
WHERE ISNULL(a.SponsorFSB1End, @NullDate) <> ISNULL(e.SponsorFSB1End, @NullDate)
   OR ISNULL(a.SponsorFSB1ExtEnd, @NullDate) <> ISNULL(e.SponsorFSB1ExtEnd, @NullDate)
   OR ISNULL(a.SponsorFSB2Start, @NullDate) <> ISNULL(e.SponsorFSB2Start, @NullDate)
   OR ISNULL(a.SponsorFSB2End, @NullDate) <> ISNULL(e.SponsorFSB2End, @NullDate)
   OR ISNULL(a.SponsorFSB3Start, @NullDate) <> ISNULL(e.SponsorFSB3Start, @NullDate)
   OR ISNULL(a.SponsorFSB3End, @NullDate) <> ISNULL(e.SponsorFSB3End, @NullDate)
ORDER BY
    e.SponsorID,
    e.SponsorFSB1Start,
    e.FSBType,
    e.OrderDate,
    e.OrderID;

-------------------------------------------------------------------------------
-- 14. Rule checks on actual dbo.FSBTrackings.
-------------------------------------------------------------------------------

-- A completed FSB window should have exactly 2 tracking rows.
SELECT
    'FSB_TYPE_COUNT_NOT_EQUAL_2' AS Issue,
    PromotionID,
    SponsorID,
    SponsorFSB1Start,
    FSBType,
    COUNT(*) AS ActualRows
FROM #V_Actual
GROUP BY
    PromotionID,
    SponsorID,
    SponsorFSB1Start,
    FSBType
HAVING COUNT(*) <> 2
ORDER BY
    SponsorID,
    SponsorFSB1Start,
    FSBType;

-- No duplicate tracking rows for the same business key.
SELECT
    'DUPLICATE_TRACKING_KEY' AS Issue,
    PromotionID,
    SponsorID,
    PromoterID,
    OrderID,
    FSBType,
    SponsorFSB1Start,
    COUNT(*) AS DuplicateCount
FROM #V_Actual
GROUP BY
    PromotionID,
    SponsorID,
    PromoterID,
    OrderID,
    FSBType,
    SponsorFSB1Start
HAVING COUNT(*) > 1
ORDER BY
    SponsorID,
    SponsorFSB1Start,
    FSBType,
    OrderID;

-- A promoter should not be counted more than once in the same sponsor FSB cycle.
SELECT
    'PROMOTER_COUNTED_MORE_THAN_ONCE_IN_CYCLE' AS Issue,
    PromotionID,
    SponsorID,
    SponsorFSB1Start,
    PromoterID,
    COUNT(*) AS TimesCounted,
    MIN(FSBType) AS FirstFSBTypeSeen,
    MAX(FSBType) AS LastFSBTypeSeen,
    MIN(OrderID) AS FirstOrderIDSeen,
    MAX(OrderID) AS LastOrderIDSeen
FROM #V_Actual
GROUP BY
    PromotionID,
    SponsorID,
    SponsorFSB1Start,
    PromoterID
HAVING COUNT(*) > 1
ORDER BY
    SponsorID,
    SponsorFSB1Start,
    PromoterID;

-- FSB2 requires regular FSB1, not FSB1_EXT.
;WITH ActualCounts AS
(
    SELECT
        PromotionID,
        SponsorID,
        SponsorFSB1Start,
        SUM(CASE WHEN FSBType = 'FSB1' THEN 1 ELSE 0 END) AS FSB1Rows,
        SUM(CASE WHEN FSBType = 'FSB1_EXT' THEN 1 ELSE 0 END) AS FSB1ExtRows,
        SUM(CASE WHEN FSBType = 'FSB2' THEN 1 ELSE 0 END) AS FSB2Rows,
        SUM(CASE WHEN FSBType = 'FSB3' THEN 1 ELSE 0 END) AS FSB3Rows
    FROM #V_Actual
    GROUP BY
        PromotionID,
        SponsorID,
        SponsorFSB1Start
)
SELECT
    'FSB2_OR_FSB3_WITHOUT_REQUIRED_PRIOR_WINDOWS' AS Issue,
    *
FROM ActualCounts
WHERE (FSB2Rows > 0 AND FSB1Rows <> 2)
   OR (FSB3Rows > 0 AND (FSB1Rows <> 2 OR FSB2Rows <> 2))
   OR (FSB1ExtRows > 0 AND (FSB2Rows > 0 OR FSB3Rows > 0))
ORDER BY
    SponsorID,
    SponsorFSB1Start;

-------------------------------------------------------------------------------
-- 15. Sponsor-level expected vs actual counts.
-------------------------------------------------------------------------------

;WITH ExpectedAgg AS
(
    SELECT
        PromotionID,
        SponsorID,
        SponsorFSB1Start,
        SUM(CASE WHEN FSBType = 'FSB1' THEN 1 ELSE 0 END) AS ExpectedFSB1,
        SUM(CASE WHEN FSBType = 'FSB1_EXT' THEN 1 ELSE 0 END) AS ExpectedFSB1Ext,
        SUM(CASE WHEN FSBType = 'FSB2' THEN 1 ELSE 0 END) AS ExpectedFSB2,
        SUM(CASE WHEN FSBType = 'FSB3' THEN 1 ELSE 0 END) AS ExpectedFSB3,
        COUNT(*) AS ExpectedTotal
    FROM #V_Expected
    GROUP BY
        PromotionID,
        SponsorID,
        SponsorFSB1Start
),
ActualAgg AS
(
    SELECT
        PromotionID,
        SponsorID,
        SponsorFSB1Start,
        SUM(CASE WHEN FSBType = 'FSB1' THEN 1 ELSE 0 END) AS ActualFSB1,
        SUM(CASE WHEN FSBType = 'FSB1_EXT' THEN 1 ELSE 0 END) AS ActualFSB1Ext,
        SUM(CASE WHEN FSBType = 'FSB2' THEN 1 ELSE 0 END) AS ActualFSB2,
        SUM(CASE WHEN FSBType = 'FSB3' THEN 1 ELSE 0 END) AS ActualFSB3,
        COUNT(*) AS ActualTotal
    FROM #V_Actual
    GROUP BY
        PromotionID,
        SponsorID,
        SponsorFSB1Start
)
SELECT
    COALESCE(e.PromotionID, a.PromotionID) AS PromotionID,
    COALESCE(e.SponsorID, a.SponsorID) AS SponsorID,
    COALESCE(e.SponsorFSB1Start, a.SponsorFSB1Start) AS SponsorFSB1Start,
    ISNULL(e.ExpectedFSB1, 0) AS ExpectedFSB1,
    ISNULL(a.ActualFSB1, 0) AS ActualFSB1,
    ISNULL(e.ExpectedFSB1Ext, 0) AS ExpectedFSB1Ext,
    ISNULL(a.ActualFSB1Ext, 0) AS ActualFSB1Ext,
    ISNULL(e.ExpectedFSB2, 0) AS ExpectedFSB2,
    ISNULL(a.ActualFSB2, 0) AS ActualFSB2,
    ISNULL(e.ExpectedFSB3, 0) AS ExpectedFSB3,
    ISNULL(a.ActualFSB3, 0) AS ActualFSB3,
    ISNULL(e.ExpectedTotal, 0) AS ExpectedTotal,
    ISNULL(a.ActualTotal, 0) AS ActualTotal
FROM ExpectedAgg e
FULL OUTER JOIN ActualAgg a
    ON a.PromotionID = e.PromotionID
   AND a.SponsorID = e.SponsorID
   AND a.SponsorFSB1Start = e.SponsorFSB1Start
WHERE ISNULL(e.ExpectedFSB1, 0) <> ISNULL(a.ActualFSB1, 0)
   OR ISNULL(e.ExpectedFSB1Ext, 0) <> ISNULL(a.ActualFSB1Ext, 0)
   OR ISNULL(e.ExpectedFSB2, 0) <> ISNULL(a.ActualFSB2, 0)
   OR ISNULL(e.ExpectedFSB3, 0) <> ISNULL(a.ActualFSB3, 0)
   OR ISNULL(e.ExpectedTotal, 0) <> ISNULL(a.ActualTotal, 0)
ORDER BY
    SponsorID,
    SponsorFSB1Start;
