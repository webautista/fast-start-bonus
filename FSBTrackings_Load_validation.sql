/*
    Validation script for dbo.FSBTrackings_Load with audited candidate universe.

    Purpose:
    1. Recalculate expected dbo.FSBCandidates rows for a Promotion/Sponsor scope.
    2. Recalculate expected dbo.FSBTrackings rows, including NO_FSB, for the same scope.
    3. Compare expected vs actual rows after dbo.FSBTrackings_Load runs.

    Usage:
    - Set @PromotionID and optional @SponsorID.
    - Run after executing dbo.FSBTrackings_Load.
*/

SET NOCOUNT ON;

DECLARE @PromotionID BIGINT;
DECLARE @SponsorID BIGINT = NULL; -- set a SponsorID to validate a single sponsor

-- Example:
SELECT @PromotionID = PromotionID
FROM dbo.Promotions
WHERE Code = 'FSB_2026_MAIN';

-- TODO: Set this value before running if the SELECT above is not used.
-- SET @PromotionID = 123;

DECLARE @NullDate DATETIME = CONVERT(DATETIME, '19000101', 112);

IF @PromotionID IS NULL
BEGIN
    RAISERROR('Set @PromotionID before running validation.', 16, 1);
    RETURN;
END;

IF NOT EXISTS
(
    SELECT 1
    FROM dbo.Promotions
    WHERE PromotionID = @PromotionID
)
BEGIN
    RAISERROR('Invalid @PromotionID.', 16, 1);
    RETURN;
END;

-------------------------------------------------------------------------------
-- Cleanup
-------------------------------------------------------------------------------

IF OBJECT_ID('tempdb..#V_ScopeSponsors') IS NOT NULL DROP TABLE #V_ScopeSponsors;
IF OBJECT_ID('tempdb..#V_Universe') IS NOT NULL DROP TABLE #V_Universe;
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
IF OBJECT_ID('tempdb..#V_Classified') IS NOT NULL DROP TABLE #V_Classified;
IF OBJECT_ID('tempdb..#V_SelectedKeys') IS NOT NULL DROP TABLE #V_SelectedKeys;
IF OBJECT_ID('tempdb..#V_OrderIDs') IS NOT NULL DROP TABLE #V_OrderIDs;
IF OBJECT_ID('tempdb..#V_OrderPayments') IS NOT NULL DROP TABLE #V_OrderPayments;
IF OBJECT_ID('tempdb..#V_ExpectedTrackings') IS NOT NULL DROP TABLE #V_ExpectedTrackings;
IF OBJECT_ID('tempdb..#V_ActualTrackings') IS NOT NULL DROP TABLE #V_ActualTrackings;
IF OBJECT_ID('tempdb..#V_ActualCandidates') IS NOT NULL DROP TABLE #V_ActualCandidates;

-------------------------------------------------------------------------------
-- 1. Scope sponsors
-------------------------------------------------------------------------------

CREATE TABLE #V_ScopeSponsors
(
    PromotionID BIGINT NOT NULL,
    SponsorID BIGINT NOT NULL,
    SponsorUserID BIGINT NOT NULL,
    SponsorFSB1Start DATETIME NOT NULL
);

INSERT INTO #V_ScopeSponsors
(
    PromotionID,
    SponsorID,
    SponsorUserID,
    SponsorFSB1Start
)
SELECT DISTINCT
    @PromotionID AS PromotionID,
    sponsor.PromoterID AS SponsorID,
    sponsor.UserProfileID AS SponsorUserID,
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
-- 2. Expected complete candidate universe
-------------------------------------------------------------------------------

CREATE TABLE #V_Universe
(
    PromotionID BIGINT NOT NULL,
    SponsorID BIGINT NOT NULL,
    SponsorUserID BIGINT NOT NULL,
    SponsorFSB1Start DATETIME NOT NULL,

    CandidateKey BIGINT NOT NULL,
    CandidateType VARCHAR(20) NOT NULL,

    PromoterID BIGINT NULL,
    CustomerID BIGINT NOT NULL,
    ParticipantUserID BIGINT NOT NULL,

    OrderID BIGINT NOT NULL,
    OrderDate DATETIME NOT NULL,
    ProductID INT NOT NULL,
    OrderStatus VARCHAR(20) NOT NULL,

    IsExcludedProduct BIT NOT NULL,
    IsStaticEligible BIT NOT NULL,
    StaticEligibilityReason VARCHAR(200) NULL,

    IsEliteTravelAdvantagePro BIT NULL,
    IsPromoCouponApplied BIT NULL,
    IsPermanentPromoCouponApplied BIT NULL,
    FreeCommission BIT NULL,
    IsDagCustomer BIT NULL,
    IsCreatedWithPromoPrice BIT NULL
);

;WITH PromoterUniverse AS
(
    SELECT
        @PromotionID AS PromotionID,
        scope.SponsorID,
        scope.SponsorUserID,
        scope.SponsorFSB1Start,

        CAST(child.PromoterID AS BIGINT) AS CandidateKey,
        CAST('PROMOTER' AS VARCHAR(20)) AS CandidateType,

        CAST(child.PromoterID AS BIGINT) AS PromoterID,
        CAST(c.CustomerID AS BIGINT) AS CustomerID,
        CAST(upChild.UserID AS BIGINT) AS ParticipantUserID,

        CAST(o.OrderID AS BIGINT) AS OrderID,
        o.OrderDate,
        o.ProductID,
        CAST(ISNULL(o.[Status], '') AS VARCHAR(20)) AS OrderStatus,

        CAST(CASE WHEN ppExcluded.PromotionProductID IS NULL THEN 0 ELSE 1 END AS BIT) AS IsExcludedProduct,
        CAST
        (
            CASE
                WHEN child.Active <> 1 THEN 0
                WHEN NOT (child.FreeType = 0 OR child.FreeType IS NULL) THEN 0
                WHEN upChild.SpecialCode IS NOT NULL THEN 0
                WHEN ISNULL(o.[Status], '') <> 'Active' THEN 0
                WHEN ppExcluded.PromotionProductID IS NOT NULL THEN 0
                WHEN o.ProductID NOT IN (20, 23, 25, 26, 27, 28) THEN 0
                WHEN ISNULL(o.FreeCommission, 0) <> 0 THEN 0
                WHEN ISNULL(o.IsDagCustomer, 0) <> 0 THEN 0
                WHEN ISNULL(o.IsCreatedWithPromoPrice, 0) <> 0 THEN 0
                ELSE 1
            END
        AS BIT) AS IsStaticEligible,
        CAST
        (
            CASE
                WHEN child.Active <> 1 THEN 'PROMOTER_INACTIVE'
                WHEN NOT (child.FreeType = 0 OR child.FreeType IS NULL) THEN 'PROMOTER_FREETYPE'
                WHEN upChild.SpecialCode IS NOT NULL THEN 'PROMOTER_SPECIALCODE'
                WHEN ISNULL(o.[Status], '') <> 'Active' THEN 'ORDER_STATUS'
                WHEN ppExcluded.PromotionProductID IS NOT NULL THEN 'EXCLUDED_PRODUCT'
                WHEN o.ProductID NOT IN (20, 23, 25, 26, 27, 28) THEN 'PROMOTER_PRODUCT'
                WHEN ISNULL(o.FreeCommission, 0) <> 0 THEN 'FREE_COMMISSION'
                WHEN ISNULL(o.IsDagCustomer, 0) <> 0 THEN 'DAG_CUSTOMER'
                WHEN ISNULL(o.IsCreatedWithPromoPrice, 0) <> 0 THEN 'PROMO_PRICE'
                ELSE NULL
            END
        AS VARCHAR(200)) AS StaticEligibilityReason,

        CAST(o.IsEliteTravelAdvantagePro AS BIT) AS IsEliteTravelAdvantagePro,
        CAST(o.IsPromoCouponApplied AS BIT) AS IsPromoCouponApplied,
        CAST(o.IsPermanentPromoCouponApplied AS BIT) AS IsPermanentPromoCouponApplied,
        CAST(o.FreeCommission AS BIT) AS FreeCommission,
        CAST(o.IsDagCustomer AS BIT) AS IsDagCustomer,
        CAST(o.IsCreatedWithPromoPrice AS BIT) AS IsCreatedWithPromoPrice
    FROM #V_ScopeSponsors scope
    INNER JOIN dbo.Promoters child
        ON child.SponsorID = scope.SponsorID
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
    WHERE o.OrderDate IS NOT NULL
      AND o.OrderDate >= scope.SponsorFSB1Start
      AND o.OrderDate <= DATEADD(DAY, 21, scope.SponsorFSB1Start)
),
CustomerUniverse AS
(
    SELECT
        @PromotionID AS PromotionID,
        scope.SponsorID,
        scope.SponsorUserID,
        scope.SponsorFSB1Start,

        -1 * CAST(c.CustomerID AS BIGINT) AS CandidateKey,
        CAST('CUSTOMER' AS VARCHAR(20)) AS CandidateType,

        CAST(NULL AS BIGINT) AS PromoterID,
        CAST(c.CustomerID AS BIGINT) AS CustomerID,
        CAST(c.UserID AS BIGINT) AS ParticipantUserID,

        CAST(o.OrderID AS BIGINT) AS OrderID,
        o.OrderDate,
        o.ProductID,
        CAST(ISNULL(o.[Status], '') AS VARCHAR(20)) AS OrderStatus,

        CAST(CASE WHEN ppExcluded.PromotionProductID IS NULL THEN 0 ELSE 1 END AS BIT) AS IsExcludedProduct,
        CAST
        (
            CASE
                WHEN ISNULL(o.[Status], '') <> 'Active' THEN 0
                WHEN ppExcluded.PromotionProductID IS NOT NULL THEN 0
                WHEN o.ProductID <> 20 THEN 0
                WHEN ISNULL(o.IsEliteTravelAdvantagePro, 0) = 0 THEN 0
                WHEN ISNULL(o.IsPromoCouponApplied, 0) <> 0 THEN 0
                WHEN ISNULL(o.IsPermanentPromoCouponApplied, 0) <> 0 THEN 0
                WHEN ISNULL(o.FreeCommission, 0) <> 0 THEN 0
                WHEN ISNULL(o.IsDagCustomer, 0) <> 0 THEN 0
                WHEN ISNULL(o.IsCreatedWithPromoPrice, 0) <> 0 THEN 0
                ELSE 1
            END
        AS BIT) AS IsStaticEligible,
        CAST
        (
            CASE
                WHEN ISNULL(o.[Status], '') <> 'Active' THEN 'ORDER_STATUS'
                WHEN ppExcluded.PromotionProductID IS NOT NULL THEN 'EXCLUDED_PRODUCT'
                WHEN o.ProductID <> 20 THEN 'CUSTOMER_PRODUCT'
                WHEN ISNULL(o.IsEliteTravelAdvantagePro, 0) = 0 THEN 'NOT_ELITE'
                WHEN ISNULL(o.IsPromoCouponApplied, 0) <> 0 THEN 'PROMO_COUPON'
                WHEN ISNULL(o.IsPermanentPromoCouponApplied, 0) <> 0 THEN 'PERMANENT_PROMO_COUPON'
                WHEN ISNULL(o.FreeCommission, 0) <> 0 THEN 'FREE_COMMISSION'
                WHEN ISNULL(o.IsDagCustomer, 0) <> 0 THEN 'DAG_CUSTOMER'
                WHEN ISNULL(o.IsCreatedWithPromoPrice, 0) <> 0 THEN 'PROMO_PRICE'
                ELSE NULL
            END
        AS VARCHAR(200)) AS StaticEligibilityReason,

        CAST(o.IsEliteTravelAdvantagePro AS BIT) AS IsEliteTravelAdvantagePro,
        CAST(o.IsPromoCouponApplied AS BIT) AS IsPromoCouponApplied,
        CAST(o.IsPermanentPromoCouponApplied AS BIT) AS IsPermanentPromoCouponApplied,
        CAST(o.FreeCommission AS BIT) AS FreeCommission,
        CAST(o.IsDagCustomer AS BIT) AS IsDagCustomer,
        CAST(o.IsCreatedWithPromoPrice AS BIT) AS IsCreatedWithPromoPrice
    FROM #V_ScopeSponsors scope
    INNER JOIN dbo.MWRCustomers c
        ON c.SponsorMemberID = scope.SponsorUserID
       AND c.UserID <> scope.SponsorUserID
    INNER JOIN dbo.[Order] o
        ON o.CustomerID = c.CustomerID
    LEFT JOIN dbo.PromotionProducts ppExcluded
        ON ppExcluded.PromotionID = @PromotionID
       AND ppExcluded.ProductID = o.ProductID
       AND ppExcluded.IsExcluded = 1
    WHERE o.OrderDate IS NOT NULL
      AND o.OrderDate >= scope.SponsorFSB1Start
      AND o.OrderDate <= DATEADD(DAY, 21, scope.SponsorFSB1Start)
)
INSERT INTO #V_Universe
(
    PromotionID,
    SponsorID,
    SponsorUserID,
    SponsorFSB1Start,
    CandidateKey,
    CandidateType,
    PromoterID,
    CustomerID,
    ParticipantUserID,
    OrderID,
    OrderDate,
    ProductID,
    OrderStatus,
    IsExcludedProduct,
    IsStaticEligible,
    StaticEligibilityReason,
    IsEliteTravelAdvantagePro,
    IsPromoCouponApplied,
    IsPermanentPromoCouponApplied,
    FreeCommission,
    IsDagCustomer,
    IsCreatedWithPromoPrice
)
SELECT
    PromotionID,
    SponsorID,
    SponsorUserID,
    SponsorFSB1Start,
    CandidateKey,
    CandidateType,
    PromoterID,
    CustomerID,
    ParticipantUserID,
    OrderID,
    OrderDate,
    ProductID,
    OrderStatus,
    IsExcludedProduct,
    IsStaticEligible,
    StaticEligibilityReason,
    IsEliteTravelAdvantagePro,
    IsPromoCouponApplied,
    IsPermanentPromoCouponApplied,
    FreeCommission,
    IsDagCustomer,
    IsCreatedWithPromoPrice
FROM PromoterUniverse

UNION ALL

SELECT
    PromotionID,
    SponsorID,
    SponsorUserID,
    SponsorFSB1Start,
    CandidateKey,
    CandidateType,
    PromoterID,
    CustomerID,
    ParticipantUserID,
    OrderID,
    OrderDate,
    ProductID,
    OrderStatus,
    IsExcludedProduct,
    IsStaticEligible,
    StaticEligibilityReason,
    IsEliteTravelAdvantagePro,
    IsPromoCouponApplied,
    IsPermanentPromoCouponApplied,
    FreeCommission,
    IsDagCustomer,
    IsCreatedWithPromoPrice
FROM CustomerUniverse
OPTION (RECOMPILE);

CREATE CLUSTERED INDEX CX_V_Universe
ON #V_Universe
(
    PromotionID,
    SponsorID,
    SponsorFSB1Start,
    CandidateType,
    CandidateKey,
    OrderDate,
    OrderID
);

-------------------------------------------------------------------------------
-- 3. Expected base orders: first static-eligible order per associated entity
-------------------------------------------------------------------------------

CREATE TABLE #V_BaseOrders
(
    PromotionID BIGINT NOT NULL,
    SponsorID BIGINT NOT NULL,
    PromoterID BIGINT NOT NULL,
    CustomerID BIGINT NOT NULL,
    ParticipantUserID BIGINT NOT NULL,
    CandidateType VARCHAR(20) NOT NULL,
    OrderID BIGINT NOT NULL,
    OrderDate DATETIME NOT NULL,
    SponsorFSB1Start DATETIME NOT NULL,
    SponsorFSB1MaxEnd DATETIME NOT NULL,
    SponsorFSB1ExtMaxEnd DATETIME NOT NULL
);

;WITH RankedBase AS
(
    SELECT
        u.PromotionID,
        u.SponsorID,
        u.CandidateKey AS PromoterID,
        u.CustomerID,
        u.ParticipantUserID,
        u.CandidateType,
        u.OrderID,
        u.OrderDate,
        u.SponsorFSB1Start,
        DATEADD(DAY, 7, u.SponsorFSB1Start) AS SponsorFSB1MaxEnd,
        DATEADD(DAY, 14, u.SponsorFSB1Start) AS SponsorFSB1ExtMaxEnd,
        ROW_NUMBER() OVER
        (
            PARTITION BY
                u.PromotionID,
                u.SponsorID,
                u.SponsorFSB1Start,
                u.CandidateType,
                u.CandidateKey
            ORDER BY
                u.OrderDate,
                u.OrderID
        ) AS rn
    FROM #V_Universe u
    WHERE u.IsStaticEligible = 1
)
INSERT INTO #V_BaseOrders
(
    PromotionID,
    SponsorID,
    PromoterID,
    CustomerID,
    ParticipantUserID,
    CandidateType,
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
    CustomerID,
    ParticipantUserID,
    CandidateType,
    OrderID,
    OrderDate,
    SponsorFSB1Start,
    SponsorFSB1MaxEnd,
    SponsorFSB1ExtMaxEnd
FROM RankedBase
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

CREATE INDEX IX_V_BaseOrders_OrderDate
ON #V_BaseOrders
(
    SponsorID,
    SponsorFSB1Start,
    OrderDate,
    OrderID
);

-------------------------------------------------------------------------------
-- 4. Expected FSB1 / FSB1_EXT / FSB2 / FSB3 / NO_FSB classification
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
FROM #V_FSB1ExtWindowRows ext;

CREATE CLUSTERED INDEX CX_V_FSB1ExtRows
ON #V_FSB1ExtRows
(
    PromotionID,
    SponsorID,
    SponsorFSB1Start,
    PromoterID
);

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
LEFT JOIN #V_FSB2Qualified q
    ON q.PromotionID = f2.PromotionID
   AND q.SponsorID = f2.SponsorID
   AND q.SponsorFSB1Start = f2.SponsorFSB1Start
WHERE (q.PromotionID IS NOT NULL AND f2.FSB2Rank <= 2)
   OR (q.PromotionID IS NULL);

CREATE CLUSTERED INDEX CX_V_FSB2Rows
ON #V_FSB2Rows
(
    PromotionID,
    SponsorID,
    SponsorFSB1Start,
    PromoterID
);

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
FROM #V_FSB3WindowRows f3;

CREATE CLUSTERED INDEX CX_V_FSB3Rows
ON #V_FSB3Rows
(
    PromotionID,
    SponsorID,
    SponsorFSB1Start,
    PromoterID
);

CREATE TABLE #V_Classified
(
    PromotionID BIGINT NOT NULL,
    SponsorID BIGINT NOT NULL,
    PromoterID BIGINT NOT NULL,
    CustomerID BIGINT NOT NULL,
    ParticipantUserID BIGINT NOT NULL,
    CandidateType VARCHAR(20) NOT NULL,
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

INSERT INTO #V_Classified
SELECT
    f1Rows.PromotionID,
    f1Rows.SponsorID,
    f1Rows.PromoterID,
    f1Rows.CustomerID,
    f1Rows.ParticipantUserID,
    f1Rows.CandidateType,
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

INSERT INTO #V_Classified
SELECT
    extRows.PromotionID,
    extRows.SponsorID,
    extRows.PromoterID,
    extRows.CustomerID,
    extRows.ParticipantUserID,
    extRows.CandidateType,
    extRows.OrderID,
    extRows.OrderDate,
    'FSB1_EXT' AS FSBType,
    extRows.SponsorFSB1Start,
    ISNULL(f1Ext.FSB1EndDate, extRows.SponsorFSB1MaxEnd) AS SponsorFSB1End,
    extRows.SponsorFSB1ExtMaxEnd AS SponsorFSB1ExtEnd,
    NULL AS SponsorFSB2Start,
    NULL AS SponsorFSB2End,
    NULL AS SponsorFSB3Start,
    NULL AS SponsorFSB3End
FROM #V_FSB1ExtRows extRows
LEFT JOIN #V_FSB1ExtQualified f1Ext
    ON f1Ext.PromotionID = extRows.PromotionID
   AND f1Ext.SponsorID = extRows.SponsorID
   AND f1Ext.SponsorFSB1Start = extRows.SponsorFSB1Start;

INSERT INTO #V_Classified
SELECT
    f2Rows.PromotionID,
    f2Rows.SponsorID,
    f2Rows.PromoterID,
    f2Rows.CustomerID,
    f2Rows.ParticipantUserID,
    f2Rows.CandidateType,
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
LEFT JOIN #V_FSB2Qualified f2
    ON f2.PromotionID = f2Rows.PromotionID
   AND f2.SponsorID = f2Rows.SponsorID
   AND f2.SponsorFSB1Start = f2Rows.SponsorFSB1Start
LEFT JOIN #V_FSB3Qualified f3
    ON f3.PromotionID = f2Rows.PromotionID
   AND f3.SponsorID = f2Rows.SponsorID
   AND f3.SponsorFSB1Start = f2Rows.SponsorFSB1Start;

INSERT INTO #V_Classified
SELECT
    f3Rows.PromotionID,
    f3Rows.SponsorID,
    f3Rows.PromoterID,
    f3Rows.CustomerID,
    f3Rows.ParticipantUserID,
    f3Rows.CandidateType,
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
LEFT JOIN #V_FSB3Qualified f3
    ON f3.PromotionID = f3Rows.PromotionID
   AND f3.SponsorID = f3Rows.SponsorID
   AND f3.SponsorFSB1Start = f3Rows.SponsorFSB1Start;

CREATE CLUSTERED INDEX CX_V_Classified
ON #V_Classified
(
    PromotionID,
    SponsorID,
    SponsorFSB1Start,
    FSBType,
    PromoterID
);

SELECT DISTINCT
    PromotionID,
    SponsorID,
    SponsorFSB1Start,
    PromoterID,
    OrderID
INTO #V_SelectedKeys
FROM #V_Classified;

CREATE UNIQUE CLUSTERED INDEX CX_V_SelectedKeys
ON #V_SelectedKeys
(
    PromotionID,
    SponsorID,
    SponsorFSB1Start,
    PromoterID,
    OrderID
);

INSERT INTO #V_Classified
SELECT
    b.PromotionID,
    b.SponsorID,
    b.PromoterID,
    b.CustomerID,
    b.ParticipantUserID,
    b.CandidateType,
    b.OrderID,
    b.OrderDate,
    'NO_FSB' AS FSBType,
    b.SponsorFSB1Start,
    ISNULL(f1.FSB1EndDate, b.SponsorFSB1MaxEnd) AS SponsorFSB1End,
    b.SponsorFSB1ExtMaxEnd AS SponsorFSB1ExtEnd,
    f1.FSB2StartDate AS SponsorFSB2Start,
    f2.FSB2EndDate AS SponsorFSB2End,
    f2.FSB3StartDate AS SponsorFSB3Start,
    f3.FSB3EndDate AS SponsorFSB3End
FROM #V_BaseOrders b
LEFT JOIN #V_FSB1Completion f1
    ON f1.PromotionID = b.PromotionID
   AND f1.SponsorID = b.SponsorID
   AND f1.SponsorFSB1Start = b.SponsorFSB1Start
LEFT JOIN #V_FSB2Qualified f2
    ON f2.PromotionID = b.PromotionID
   AND f2.SponsorID = b.SponsorID
   AND f2.SponsorFSB1Start = b.SponsorFSB1Start
LEFT JOIN #V_FSB3Qualified f3
    ON f3.PromotionID = b.PromotionID
   AND f3.SponsorID = b.SponsorID
   AND f3.SponsorFSB1Start = b.SponsorFSB1Start
WHERE NOT EXISTS
(
    SELECT 1
    FROM #V_SelectedKeys sk
    WHERE sk.PromotionID = b.PromotionID
      AND sk.SponsorID = b.SponsorID
      AND sk.SponsorFSB1Start = b.SponsorFSB1Start
      AND sk.PromoterID = b.PromoterID
      AND sk.OrderID = b.OrderID
);

-------------------------------------------------------------------------------
-- 5. Expected payments and expected tracking rows
-------------------------------------------------------------------------------

SELECT DISTINCT
    OrderID
INTO #V_OrderIDs
FROM #V_Classified;

CREATE UNIQUE CLUSTERED INDEX CX_V_OrderIDs
ON #V_OrderIDs (OrderID);

;WITH RankedPayments AS
(
    SELECT
        rph.OrderID,
        rph.ID,
        ROW_NUMBER() OVER
        (
            PARTITION BY rph.OrderID
            ORDER BY rph.CreateDate, rph.ID
        ) AS PaymentRank
    FROM dbo.RecurringPaymentsHistory rph
    INNER JOIN #V_OrderIDs oi
        ON oi.OrderID = rph.OrderID
    WHERE rph.Status = 'SUCCESS'
      AND ISNULL(rph.Reverted, 0) = 0
)
SELECT
    oi.OrderID,
    rp1.ID AS FirstRPHID,
    rp2.ID AS SecondRPHID
INTO #V_OrderPayments
FROM #V_OrderIDs oi
LEFT JOIN RankedPayments rp1
    ON rp1.OrderID = oi.OrderID
   AND rp1.PaymentRank = 1
LEFT JOIN RankedPayments rp2
    ON rp2.OrderID = oi.OrderID
   AND rp2.PaymentRank = 2;

CREATE UNIQUE CLUSTERED INDEX CX_V_OrderPayments
ON #V_OrderPayments (OrderID);

SELECT
    c.PromotionID,
    c.SponsorID,
    c.PromoterID,
    c.CustomerID,
    c.ParticipantUserID,
    c.CandidateType,
    c.OrderID,
    c.FSBType,
    c.SponsorFSB1Start,
    c.SponsorFSB1End,
    c.SponsorFSB1ExtEnd,
    c.SponsorFSB2Start,
    c.SponsorFSB2End,
    c.SponsorFSB3Start,
    c.SponsorFSB3End,
    op.FirstRPHID,
    op.SecondRPHID
INTO #V_ExpectedTrackings
FROM #V_Classified c
LEFT JOIN #V_OrderPayments op
    ON op.OrderID = c.OrderID;

CREATE CLUSTERED INDEX CX_V_ExpectedTrackings
ON #V_ExpectedTrackings
(
    PromotionID,
    SponsorID,
    SponsorFSB1Start,
    FSBType,
    PromoterID
);

-------------------------------------------------------------------------------
-- 6. Actual current FSBCandidates / FSBTrackings rows in the same scope
-------------------------------------------------------------------------------

SELECT
    c.PromotionID,
    c.SponsorID,
    c.SponsorUserID,
    c.SponsorFSB1Start,
    c.CandidateKey,
    c.CandidateType,
    c.PromoterID,
    c.CustomerID,
    c.ParticipantUserID,
    c.OrderID,
    c.OrderDate,
    c.ProductID,
    c.OrderStatus,
    c.IsExcludedProduct,
    c.IsStaticEligible,
    c.StaticEligibilityReason
INTO #V_ActualCandidates
FROM dbo.FSBCandidates c
INNER JOIN #V_ScopeSponsors scope
    ON scope.PromotionID = c.PromotionID
   AND scope.SponsorID = c.SponsorID
   AND scope.SponsorFSB1Start = c.SponsorFSB1Start
WHERE c.PromotionID = @PromotionID
  AND c.IsCurrent = 1;

CREATE CLUSTERED INDEX CX_V_ActualCandidates
ON #V_ActualCandidates
(
    PromotionID,
    SponsorID,
    SponsorFSB1Start,
    CandidateType,
    OrderID
);

SELECT
    ft.PromotionID,
    ft.SponsorID,
    ft.PromoterID,
    ft.CustomerID,
    ft.ParticipantUserID,
    ft.CandidateType,
    ft.OrderID,
    ft.FSBType,
    ft.SponsorFSB1Start,
    ft.SponsorFSB1End,
    ft.SponsorFSB1ExtEnd,
    ft.SponsorFSB2Start,
    ft.SponsorFSB2End,
    ft.SponsorFSB3Start,
    ft.SponsorFSB3End,
    ft.FirstRPHID,
    ft.SecondRPHID
INTO #V_ActualTrackings
FROM dbo.FSBTrackings ft
INNER JOIN #V_ScopeSponsors scope
    ON scope.PromotionID = ft.PromotionID
   AND scope.SponsorID = ft.SponsorID
   AND scope.SponsorFSB1Start = ft.SponsorFSB1Start
WHERE ft.PromotionID = @PromotionID
  AND ft.IsCurrent = 1;

CREATE CLUSTERED INDEX CX_V_ActualTrackings
ON #V_ActualTrackings
(
    PromotionID,
    SponsorID,
    SponsorFSB1Start,
    FSBType,
    PromoterID
);

-------------------------------------------------------------------------------
-- 7. Universe summaries
-------------------------------------------------------------------------------

SELECT
    'EXPECTED_UNIVERSE_SUMMARY' AS ValidationSection,
    CandidateType,
    IsStaticEligible,
    COUNT(*) AS Qty
FROM #V_Universe
GROUP BY
    CandidateType,
    IsStaticEligible
ORDER BY
    CandidateType,
    IsStaticEligible DESC;

SELECT
    'ACTUAL_UNIVERSE_SUMMARY' AS ValidationSection,
    CandidateType,
    IsStaticEligible,
    COUNT(*) AS Qty
FROM #V_ActualCandidates
GROUP BY
    CandidateType,
    IsStaticEligible
ORDER BY
    CandidateType,
    IsStaticEligible DESC;

-------------------------------------------------------------------------------
-- 8. Universe detail mismatches
-------------------------------------------------------------------------------

SELECT
    'MISSING_CANDIDATE' AS ValidationSection,
    e.*
FROM #V_Universe e
LEFT JOIN #V_ActualCandidates a
    ON a.PromotionID = e.PromotionID
   AND a.SponsorID = e.SponsorID
   AND a.SponsorFSB1Start = e.SponsorFSB1Start
   AND a.CandidateType = e.CandidateType
   AND a.OrderID = e.OrderID
WHERE a.OrderID IS NULL
ORDER BY
    e.SponsorID,
    e.SponsorFSB1Start,
    e.CandidateType,
    e.OrderDate,
    e.OrderID;

SELECT
    'EXTRA_CANDIDATE' AS ValidationSection,
    a.*
FROM #V_ActualCandidates a
LEFT JOIN #V_Universe e
    ON e.PromotionID = a.PromotionID
   AND e.SponsorID = a.SponsorID
   AND e.SponsorFSB1Start = a.SponsorFSB1Start
   AND e.CandidateType = a.CandidateType
   AND e.OrderID = a.OrderID
WHERE e.OrderID IS NULL
ORDER BY
    a.SponsorID,
    a.SponsorFSB1Start,
    a.CandidateType,
    a.OrderDate,
    a.OrderID;

-------------------------------------------------------------------------------
-- 9. Tracking summaries
-------------------------------------------------------------------------------

SELECT
    'EXPECTED_TRACKING_SUMMARY' AS ValidationSection,
    FSBType,
    CandidateType,
    COUNT(*) AS Qty
FROM #V_ExpectedTrackings
GROUP BY
    FSBType,
    CandidateType
ORDER BY
    FSBType,
    CandidateType;

SELECT
    'ACTUAL_TRACKING_SUMMARY' AS ValidationSection,
    FSBType,
    CandidateType,
    COUNT(*) AS Qty
FROM #V_ActualTrackings
GROUP BY
    FSBType,
    CandidateType
ORDER BY
    FSBType,
    CandidateType;

-------------------------------------------------------------------------------
-- 10. Tracking detail mismatches
-------------------------------------------------------------------------------

SELECT
    'MISSING_TRACKING' AS ValidationSection,
    e.*
FROM #V_ExpectedTrackings e
LEFT JOIN #V_ActualTrackings a
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
    e.FSBType,
    e.OrderID,
    e.PromoterID;

SELECT
    'EXTRA_TRACKING' AS ValidationSection,
    a.*
FROM #V_ActualTrackings a
LEFT JOIN #V_ExpectedTrackings e
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
    a.FSBType,
    a.OrderID,
    a.PromoterID;

SELECT
    'TRACKING_PAYLOAD_MISMATCH' AS ValidationSection,
    e.PromotionID,
    e.SponsorID,
    e.SponsorFSB1Start,
    e.FSBType,
    e.PromoterID,
    e.OrderID,

    e.CustomerID AS ExpectedCustomerID,
    a.CustomerID AS ActualCustomerID,

    e.ParticipantUserID AS ExpectedParticipantUserID,
    a.ParticipantUserID AS ActualParticipantUserID,

    e.CandidateType AS ExpectedCandidateType,
    a.CandidateType AS ActualCandidateType,

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
    a.SponsorFSB3End AS ActualSponsorFSB3End,

    e.FirstRPHID AS ExpectedFirstRPHID,
    a.FirstRPHID AS ActualFirstRPHID,

    e.SecondRPHID AS ExpectedSecondRPHID,
    a.SecondRPHID AS ActualSecondRPHID
FROM #V_ExpectedTrackings e
INNER JOIN #V_ActualTrackings a
    ON a.PromotionID = e.PromotionID
   AND a.SponsorID = e.SponsorID
   AND a.PromoterID = e.PromoterID
   AND a.OrderID = e.OrderID
   AND a.FSBType = e.FSBType
   AND a.SponsorFSB1Start = e.SponsorFSB1Start
WHERE
       ISNULL(a.CustomerID, -1) <> ISNULL(e.CustomerID, -1)
    OR ISNULL(a.ParticipantUserID, -1) <> ISNULL(e.ParticipantUserID, -1)
    OR ISNULL(a.CandidateType, '') <> ISNULL(e.CandidateType, '')
    OR ISNULL(a.SponsorFSB1End, @NullDate) <> ISNULL(e.SponsorFSB1End, @NullDate)
    OR ISNULL(a.SponsorFSB1ExtEnd, @NullDate) <> ISNULL(e.SponsorFSB1ExtEnd, @NullDate)
    OR ISNULL(a.SponsorFSB2Start, @NullDate) <> ISNULL(e.SponsorFSB2Start, @NullDate)
    OR ISNULL(a.SponsorFSB2End, @NullDate) <> ISNULL(e.SponsorFSB2End, @NullDate)
    OR ISNULL(a.SponsorFSB3Start, @NullDate) <> ISNULL(e.SponsorFSB3Start, @NullDate)
    OR ISNULL(a.SponsorFSB3End, @NullDate) <> ISNULL(e.SponsorFSB3End, @NullDate)
    OR ISNULL(a.FirstRPHID, -1) <> ISNULL(e.FirstRPHID, -1)
    OR ISNULL(a.SecondRPHID, -1) <> ISNULL(e.SecondRPHID, -1)
ORDER BY
    e.SponsorID,
    e.SponsorFSB1Start,
    e.FSBType,
    e.OrderID,
    e.PromoterID;
