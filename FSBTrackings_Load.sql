IF OBJECT_ID('dbo.FSBTrackings_Load', 'P') IS NULL
BEGIN
    EXEC('CREATE PROCEDURE dbo.FSBTrackings_Load AS BEGIN SET NOCOUNT ON; END');
END;
GO

ALTER PROCEDURE dbo.FSBTrackings_Load
(
    @PromotionID BIGINT,
    @SponsorID BIGINT = NULL
)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @LockResult INT;
    DECLARE @LockResource NVARCHAR(255);

    DECLARE @NullDate DATETIME;

    SET @NullDate = CONVERT(DATETIME, '19000101', 112);
    SET @LockResource = 'FSBTrackings_Load_' + CAST(@PromotionID AS NVARCHAR(50));

    BEGIN TRY
        BEGIN TRANSACTION;

        EXEC @LockResult = sys.sp_getapplock
            @Resource = @LockResource,
            @LockMode = 'Exclusive',
            @LockOwner = 'Transaction',
            @LockTimeout = 30000;

        IF @LockResult < 0
        BEGIN
            RAISERROR('Could not acquire FSBTrackings_Load lock.', 16, 1);
            ROLLBACK TRANSACTION;
            RETURN;
        END;

        IF NOT EXISTS
        (
            SELECT 1
            FROM dbo.Promotions WITH (UPDLOCK, HOLDLOCK)
            WHERE PromotionID = @PromotionID
        )
        BEGIN
            RAISERROR('Invalid PromotionID.', 16, 1);
            ROLLBACK TRANSACTION;
            RETURN;
        END;

        -----------------------------------------------------------------------
        -- TEMP CLEANUP
        -----------------------------------------------------------------------

        IF OBJECT_ID('tempdb..#ScopeSponsors') IS NOT NULL DROP TABLE #ScopeSponsors;
        IF OBJECT_ID('tempdb..#Universe') IS NOT NULL DROP TABLE #Universe;
        IF OBJECT_ID('tempdb..#BaseOrders') IS NOT NULL DROP TABLE #BaseOrders;
        IF OBJECT_ID('tempdb..#FSB1WindowRows') IS NOT NULL DROP TABLE #FSB1WindowRows;
        IF OBJECT_ID('tempdb..#FSB1Qualified') IS NOT NULL DROP TABLE #FSB1Qualified;
        IF OBJECT_ID('tempdb..#FSB1NormalRows') IS NOT NULL DROP TABLE #FSB1NormalRows;
        IF OBJECT_ID('tempdb..#FSB1ExtWindowRows') IS NOT NULL DROP TABLE #FSB1ExtWindowRows;
        IF OBJECT_ID('tempdb..#FSB1ExtQualified') IS NOT NULL DROP TABLE #FSB1ExtQualified;
        IF OBJECT_ID('tempdb..#FSB1ExtRows') IS NOT NULL DROP TABLE #FSB1ExtRows;
        IF OBJECT_ID('tempdb..#FSB1Completion') IS NOT NULL DROP TABLE #FSB1Completion;
        IF OBJECT_ID('tempdb..#FSB2WindowRows') IS NOT NULL DROP TABLE #FSB2WindowRows;
        IF OBJECT_ID('tempdb..#FSB2Qualified') IS NOT NULL DROP TABLE #FSB2Qualified;
        IF OBJECT_ID('tempdb..#FSB2Rows') IS NOT NULL DROP TABLE #FSB2Rows;
        IF OBJECT_ID('tempdb..#FSB3WindowRows') IS NOT NULL DROP TABLE #FSB3WindowRows;
        IF OBJECT_ID('tempdb..#FSB3Qualified') IS NOT NULL DROP TABLE #FSB3Qualified;
        IF OBJECT_ID('tempdb..#FSB3Rows') IS NOT NULL DROP TABLE #FSB3Rows;
        IF OBJECT_ID('tempdb..#Classified') IS NOT NULL DROP TABLE #Classified;
        IF OBJECT_ID('tempdb..#SelectedKeys') IS NOT NULL DROP TABLE #SelectedKeys;
        IF OBJECT_ID('tempdb..#OrderIDs') IS NOT NULL DROP TABLE #OrderIDs;
        IF OBJECT_ID('tempdb..#OrderPayments') IS NOT NULL DROP TABLE #OrderPayments;

        -----------------------------------------------------------------------
        -- 1. SCOPE SPONSORS
        -----------------------------------------------------------------------

        CREATE TABLE #ScopeSponsors
        (
            PromotionID BIGINT NOT NULL,
            SponsorID BIGINT NOT NULL,
            SponsorUserID BIGINT NOT NULL,
            SponsorFSB1Start DATETIME NOT NULL
        );

        INSERT INTO #ScopeSponsors
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

        CREATE UNIQUE CLUSTERED INDEX CX_ScopeSponsors
        ON #ScopeSponsors
        (
            PromotionID,
            SponsorID,
            SponsorFSB1Start
        );

        -----------------------------------------------------------------------
        -- 2. COMPLETE CANDIDATE UNIVERSE
        -- One row per associated order inside SponsorFSB1Start + 21 days.
        -- Static eligibility is audited in dbo.FSBCandidates.
        -----------------------------------------------------------------------

        CREATE TABLE #Universe
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
            FROM #ScopeSponsors scope
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
            FROM #ScopeSponsors scope
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
        INSERT INTO #Universe
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

        CREATE CLUSTERED INDEX CX_Universe
        ON #Universe
        (
            PromotionID,
            SponsorID,
            SponsorFSB1Start,
            CandidateType,
            CandidateKey,
            OrderDate,
            OrderID
        );

        CREATE INDEX IX_Universe_Order
        ON #Universe (OrderID);

        -----------------------------------------------------------------------
        -- 3. REFRESH AUDIT TABLE
        -----------------------------------------------------------------------

        DELETE fc
        FROM dbo.FSBCandidates fc
        INNER JOIN #ScopeSponsors scope
            ON scope.PromotionID = fc.PromotionID
           AND scope.SponsorID = fc.SponsorID
           AND scope.SponsorFSB1Start = fc.SponsorFSB1Start
        WHERE fc.PromotionID = @PromotionID;

        INSERT INTO dbo.FSBCandidates
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
        FROM #Universe;

        -----------------------------------------------------------------------
        -- 4. BASE ORDERS FOR CLASSIFICATION
        -- One static-eligible order per associated entity in the cycle:
        --   - PROMOTER: first eligible order per sponsored promoter
        --   - CUSTOMER: first eligible order per sponsored customer
        -----------------------------------------------------------------------

        CREATE TABLE #BaseOrders
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
                c.PromotionID,
                c.SponsorID,
                c.CandidateKey AS PromoterID,
                c.CustomerID,
                c.ParticipantUserID,
                c.CandidateType,
                c.OrderID,
                c.OrderDate,
                c.SponsorFSB1Start,
                DATEADD(DAY, 7, c.SponsorFSB1Start) AS SponsorFSB1MaxEnd,
                DATEADD(DAY, 14, c.SponsorFSB1Start) AS SponsorFSB1ExtMaxEnd,
                ROW_NUMBER() OVER
                (
                    PARTITION BY
                        c.PromotionID,
                        c.SponsorID,
                        c.SponsorFSB1Start,
                        c.CandidateType,
                        c.CandidateKey
                    ORDER BY
                        c.OrderDate,
                        c.OrderID
                ) AS rn
            FROM dbo.FSBCandidates c
            INNER JOIN #ScopeSponsors scope
                ON scope.PromotionID = c.PromotionID
               AND scope.SponsorID = c.SponsorID
               AND scope.SponsorFSB1Start = c.SponsorFSB1Start
            WHERE c.PromotionID = @PromotionID
              AND c.IsStaticEligible = 1
        )
        INSERT INTO #BaseOrders
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

        CREATE CLUSTERED INDEX CX_BaseOrders
        ON #BaseOrders
        (
            PromotionID,
            SponsorID,
            SponsorFSB1Start,
            PromoterID
        );

        CREATE INDEX IX_BaseOrders_OrderID
        ON #BaseOrders (OrderID);

        CREATE INDEX IX_BaseOrders_OrderDate
        ON #BaseOrders
        (
            SponsorID,
            SponsorFSB1Start,
            OrderDate,
            OrderID
        );

        -----------------------------------------------------------------------
        -- 5. FSB1 NORMAL
        -----------------------------------------------------------------------

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
            FROM #BaseOrders b
            WHERE b.OrderDate >= b.SponsorFSB1Start
              AND b.OrderDate <= b.SponsorFSB1MaxEnd
        )
        SELECT *
        INTO #FSB1WindowRows
        FROM RankedFSB1;

        CREATE CLUSTERED INDEX CX_FSB1WindowRows
        ON #FSB1WindowRows
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
        INTO #FSB1Qualified
        FROM #FSB1WindowRows
        WHERE FSB1Rank = 2;

        CREATE UNIQUE CLUSTERED INDEX CX_FSB1Qualified
        ON #FSB1Qualified
        (
            PromotionID,
            SponsorID,
            SponsorFSB1Start
        );

        SELECT f1.*
        INTO #FSB1NormalRows
        FROM #FSB1WindowRows f1
        INNER JOIN #FSB1Qualified q
            ON q.PromotionID = f1.PromotionID
           AND q.SponsorID = f1.SponsorID
           AND q.SponsorFSB1Start = f1.SponsorFSB1Start
        WHERE f1.FSB1Rank <= 2;

        CREATE CLUSTERED INDEX CX_FSB1NormalRows
        ON #FSB1NormalRows
        (
            PromotionID,
            SponsorID,
            SponsorFSB1Start,
            PromoterID
        );

        -----------------------------------------------------------------------
        -- 6. FSB1 EXT
        -----------------------------------------------------------------------

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
            FROM #BaseOrders b
            WHERE b.OrderDate >= b.SponsorFSB1Start
              AND b.OrderDate <= b.SponsorFSB1ExtMaxEnd
              AND NOT EXISTS
              (
                  SELECT 1
                  FROM #FSB1Qualified q
                  WHERE q.PromotionID = b.PromotionID
                    AND q.SponsorID = b.SponsorID
                    AND q.SponsorFSB1Start = b.SponsorFSB1Start
              )
        )
        SELECT *
        INTO #FSB1ExtWindowRows
        FROM RankedFSB1Ext;

        CREATE CLUSTERED INDEX CX_FSB1ExtWindowRows
        ON #FSB1ExtWindowRows
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
        INTO #FSB1ExtQualified
        FROM #FSB1ExtWindowRows
        WHERE FSB1ExtRank = 2;

        CREATE UNIQUE CLUSTERED INDEX CX_FSB1ExtQualified
        ON #FSB1ExtQualified
        (
            PromotionID,
            SponsorID,
            SponsorFSB1Start
        );

        SELECT ext.*
        INTO #FSB1ExtRows
        FROM #FSB1ExtWindowRows ext;

        CREATE CLUSTERED INDEX CX_FSB1ExtRows
        ON #FSB1ExtRows
        (
            PromotionID,
            SponsorID,
            SponsorFSB1Start,
            PromoterID
        );

        -----------------------------------------------------------------------
        -- 7. FSB1 COMPLETION
        -----------------------------------------------------------------------

        SELECT
            q.PromotionID,
            q.SponsorID,
            q.SponsorFSB1Start,
            CAST('FSB1' AS VARCHAR(20)) AS FSB1CompletionType,
            q.FSB1EndDate,
            q.FSB1EndOrderID,
            q.FSB2StartDate,
            q.SponsorFSB1ExtEnd
        INTO #FSB1Completion
        FROM #FSB1Qualified q;

        CREATE UNIQUE CLUSTERED INDEX CX_FSB1Completion
        ON #FSB1Completion
        (
            PromotionID,
            SponsorID,
            SponsorFSB1Start
        );

        -----------------------------------------------------------------------
        -- 8. FSB2
        -----------------------------------------------------------------------

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
            FROM #BaseOrders b
            INNER JOIN #FSB1Completion f1
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
                  FROM #FSB1NormalRows f1Rows
                  WHERE f1Rows.PromotionID = b.PromotionID
                    AND f1Rows.SponsorID = b.SponsorID
                    AND f1Rows.SponsorFSB1Start = b.SponsorFSB1Start
                    AND f1Rows.PromoterID = b.PromoterID
              )
              AND NOT EXISTS
              (
                  SELECT 1
                  FROM #FSB1ExtRows extRows
                  WHERE extRows.PromotionID = b.PromotionID
                    AND extRows.SponsorID = b.SponsorID
                    AND extRows.SponsorFSB1Start = b.SponsorFSB1Start
                    AND extRows.PromoterID = b.PromoterID
              )
        )
        SELECT *
        INTO #FSB2WindowRows
        FROM RankedFSB2;

        CREATE CLUSTERED INDEX CX_FSB2WindowRows
        ON #FSB2WindowRows
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
        INTO #FSB2Qualified
        FROM #FSB2WindowRows
        WHERE FSB2Rank = 2;

        CREATE UNIQUE CLUSTERED INDEX CX_FSB2Qualified
        ON #FSB2Qualified
        (
            PromotionID,
            SponsorID,
            SponsorFSB1Start
        );

        SELECT f2.*
        INTO #FSB2Rows
        FROM #FSB2WindowRows f2
        LEFT JOIN #FSB2Qualified q
            ON q.PromotionID = f2.PromotionID
           AND q.SponsorID = f2.SponsorID
           AND q.SponsorFSB1Start = f2.SponsorFSB1Start
        WHERE (q.PromotionID IS NOT NULL AND f2.FSB2Rank <= 2)
           OR (q.PromotionID IS NULL);

        CREATE CLUSTERED INDEX CX_FSB2Rows
        ON #FSB2Rows
        (
            PromotionID,
            SponsorID,
            SponsorFSB1Start,
            PromoterID
        );

        -----------------------------------------------------------------------
        -- 9. FSB3
        -----------------------------------------------------------------------

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
            FROM #BaseOrders b
            INNER JOIN #FSB2Qualified f2
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
                  FROM #FSB1NormalRows f1Rows
                  WHERE f1Rows.PromotionID = b.PromotionID
                    AND f1Rows.SponsorID = b.SponsorID
                    AND f1Rows.SponsorFSB1Start = b.SponsorFSB1Start
                    AND f1Rows.PromoterID = b.PromoterID
              )
              AND NOT EXISTS
              (
                  SELECT 1
                  FROM #FSB1ExtRows extRows
                  WHERE extRows.PromotionID = b.PromotionID
                    AND extRows.SponsorID = b.SponsorID
                    AND extRows.SponsorFSB1Start = b.SponsorFSB1Start
                    AND extRows.PromoterID = b.PromoterID
              )
              AND NOT EXISTS
              (
                  SELECT 1
                  FROM #FSB2Rows f2Rows
                  WHERE f2Rows.PromotionID = b.PromotionID
                    AND f2Rows.SponsorID = b.SponsorID
                    AND f2Rows.SponsorFSB1Start = b.SponsorFSB1Start
                    AND f2Rows.PromoterID = b.PromoterID
              )
        )
        SELECT *
        INTO #FSB3WindowRows
        FROM RankedFSB3;

        CREATE CLUSTERED INDEX CX_FSB3WindowRows
        ON #FSB3WindowRows
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
        INTO #FSB3Qualified
        FROM #FSB3WindowRows
        WHERE FSB3Rank = 2;

        CREATE UNIQUE CLUSTERED INDEX CX_FSB3Qualified
        ON #FSB3Qualified
        (
            PromotionID,
            SponsorID,
            SponsorFSB1Start
        );

        SELECT f3.*
        INTO #FSB3Rows
        FROM #FSB3WindowRows f3;

        CREATE CLUSTERED INDEX CX_FSB3Rows
        ON #FSB3Rows
        (
            PromotionID,
            SponsorID,
            SponsorFSB1Start,
            PromoterID
        );

        -----------------------------------------------------------------------
        -- 10. CLASSIFIED
        -----------------------------------------------------------------------

        CREATE TABLE #Classified
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

        INSERT INTO #Classified
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
        FROM #FSB1NormalRows f1Rows
        INNER JOIN #FSB1Completion f1
            ON f1.PromotionID = f1Rows.PromotionID
           AND f1.SponsorID = f1Rows.SponsorID
           AND f1.SponsorFSB1Start = f1Rows.SponsorFSB1Start
           AND f1.FSB1CompletionType = 'FSB1'
        LEFT JOIN #FSB2Qualified f2
            ON f2.PromotionID = f1Rows.PromotionID
           AND f2.SponsorID = f1Rows.SponsorID
           AND f2.SponsorFSB1Start = f1Rows.SponsorFSB1Start
        LEFT JOIN #FSB3Qualified f3
            ON f3.PromotionID = f1Rows.PromotionID
           AND f3.SponsorID = f1Rows.SponsorID
           AND f3.SponsorFSB1Start = f1Rows.SponsorFSB1Start;

        INSERT INTO #Classified
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
        FROM #FSB1ExtRows extRows
        LEFT JOIN #FSB1ExtQualified f1Ext
            ON f1Ext.PromotionID = extRows.PromotionID
           AND f1Ext.SponsorID = extRows.SponsorID
           AND f1Ext.SponsorFSB1Start = extRows.SponsorFSB1Start;

        INSERT INTO #Classified
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
        FROM #FSB2Rows f2Rows
        INNER JOIN #FSB1Completion f1
            ON f1.PromotionID = f2Rows.PromotionID
           AND f1.SponsorID = f2Rows.SponsorID
           AND f1.SponsorFSB1Start = f2Rows.SponsorFSB1Start
        LEFT JOIN #FSB2Qualified f2
            ON f2.PromotionID = f2Rows.PromotionID
           AND f2.SponsorID = f2Rows.SponsorID
           AND f2.SponsorFSB1Start = f2Rows.SponsorFSB1Start
        LEFT JOIN #FSB3Qualified f3
            ON f3.PromotionID = f2Rows.PromotionID
           AND f3.SponsorID = f2Rows.SponsorID
           AND f3.SponsorFSB1Start = f2Rows.SponsorFSB1Start;

        INSERT INTO #Classified
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
        FROM #FSB3Rows f3Rows
        INNER JOIN #FSB1Completion f1
            ON f1.PromotionID = f3Rows.PromotionID
           AND f1.SponsorID = f3Rows.SponsorID
           AND f1.SponsorFSB1Start = f3Rows.SponsorFSB1Start
        INNER JOIN #FSB2Qualified f2
            ON f2.PromotionID = f3Rows.PromotionID
           AND f2.SponsorID = f3Rows.SponsorID
           AND f2.SponsorFSB1Start = f3Rows.SponsorFSB1Start
        LEFT JOIN #FSB3Qualified f3
            ON f3.PromotionID = f3Rows.PromotionID
           AND f3.SponsorID = f3Rows.SponsorID
           AND f3.SponsorFSB1Start = f3Rows.SponsorFSB1Start;

        CREATE CLUSTERED INDEX CX_Classified
        ON #Classified
        (
            PromotionID,
            SponsorID,
            SponsorFSB1Start,
            FSBType,
            PromoterID
        );

        CREATE INDEX IX_Classified_OrderID
        ON #Classified (OrderID);

        SELECT DISTINCT
            PromotionID,
            SponsorID,
            SponsorFSB1Start,
            PromoterID,
            OrderID
        INTO #SelectedKeys
        FROM #Classified;

        CREATE UNIQUE CLUSTERED INDEX CX_SelectedKeys
        ON #SelectedKeys
        (
            PromotionID,
            SponsorID,
            SponsorFSB1Start,
            PromoterID,
            OrderID
        );

        INSERT INTO #Classified
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
        FROM #BaseOrders b
        LEFT JOIN #FSB1Completion f1
            ON f1.PromotionID = b.PromotionID
           AND f1.SponsorID = b.SponsorID
           AND f1.SponsorFSB1Start = b.SponsorFSB1Start
        LEFT JOIN #FSB2Qualified f2
            ON f2.PromotionID = b.PromotionID
           AND f2.SponsorID = b.SponsorID
           AND f2.SponsorFSB1Start = b.SponsorFSB1Start
        LEFT JOIN #FSB3Qualified f3
            ON f3.PromotionID = b.PromotionID
           AND f3.SponsorID = b.SponsorID
           AND f3.SponsorFSB1Start = b.SponsorFSB1Start
        WHERE NOT EXISTS
        (
            SELECT 1
            FROM #SelectedKeys sk
            WHERE sk.PromotionID = b.PromotionID
              AND sk.SponsorID = b.SponsorID
              AND sk.SponsorFSB1Start = b.SponsorFSB1Start
              AND sk.PromoterID = b.PromoterID
              AND sk.OrderID = b.OrderID
        );

        -----------------------------------------------------------------------
        -- 11. PAYMENTS
        -----------------------------------------------------------------------

        SELECT DISTINCT
            OrderID
        INTO #OrderIDs
        FROM #Classified;

        CREATE UNIQUE CLUSTERED INDEX CX_OrderIDs
        ON #OrderIDs (OrderID);

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
            INNER JOIN #OrderIDs oi
                ON oi.OrderID = rph.OrderID
            WHERE rph.Status = 'SUCCESS'
              AND ISNULL(rph.Reverted, 0) = 0
        )
        SELECT
            oi.OrderID,
            rp1.ID AS FirstRPHID,
            rp2.ID AS SecondRPHID
        INTO #OrderPayments
        FROM #OrderIDs oi
        LEFT JOIN RankedPayments rp1
            ON rp1.OrderID = oi.OrderID
           AND rp1.PaymentRank = 1
        LEFT JOIN RankedPayments rp2
            ON rp2.OrderID = oi.OrderID
           AND rp2.PaymentRank = 2;

        CREATE UNIQUE CLUSTERED INDEX CX_OrderPayments
        ON #OrderPayments (OrderID);

        -----------------------------------------------------------------------
        -- 12. REFRESH TRACKINGS IN CURRENT SCOPE
        -----------------------------------------------------------------------

        DELETE ft
        FROM dbo.FSBTrackings ft
        INNER JOIN #ScopeSponsors scope
            ON scope.PromotionID = ft.PromotionID
           AND scope.SponsorID = ft.SponsorID
           AND scope.SponsorFSB1Start = ft.SponsorFSB1Start
        WHERE ft.PromotionID = @PromotionID
          AND NOT EXISTS
          (
              SELECT 1
              FROM #Classified c
              WHERE c.PromotionID = ft.PromotionID
                AND c.SponsorID = ft.SponsorID
                AND c.PromoterID = ft.PromoterID
                AND c.OrderID = ft.OrderID
                AND c.FSBType = ft.FSBType
                AND c.SponsorFSB1Start = ft.SponsorFSB1Start
          );

        -----------------------------------------------------------------------
        -- 13. INSERT TRACKINGS
        -----------------------------------------------------------------------

        INSERT INTO dbo.FSBTrackings
        (
            PromotionID,
            SponsorID,
            PromoterID,
            CustomerID,
            ParticipantUserID,
            CandidateType,
            OrderID,
            FSBType,
            SponsorFSB1Start,
            SponsorFSB1End,
            SponsorFSB1ExtEnd,
            SponsorFSB2Start,
            SponsorFSB2End,
            SponsorFSB3Start,
            SponsorFSB3End,
            FirstRPHID,
            SecondRPHID
        )
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
        FROM #Classified c
        LEFT JOIN #OrderPayments op
            ON op.OrderID = c.OrderID
        WHERE NOT EXISTS
        (
            SELECT 1
            FROM dbo.FSBTrackings ft WITH (UPDLOCK, HOLDLOCK)
            WHERE ft.PromotionID = c.PromotionID
              AND ft.SponsorID = c.SponsorID
              AND ft.PromoterID = c.PromoterID
              AND ft.OrderID = c.OrderID
              AND ft.FSBType = c.FSBType
              AND ft.SponsorFSB1Start = c.SponsorFSB1Start
        );

        -----------------------------------------------------------------------
        -- 14. UPDATE EXISTING TRACKINGS WITH CURRENT DATA
        -----------------------------------------------------------------------

        UPDATE ft
            SET
                CustomerID = c.CustomerID,
                ParticipantUserID = c.ParticipantUserID,
                CandidateType = c.CandidateType,
                SponsorFSB1End = c.SponsorFSB1End,
                SponsorFSB1ExtEnd = c.SponsorFSB1ExtEnd,
                SponsorFSB2Start = c.SponsorFSB2Start,
                SponsorFSB2End = c.SponsorFSB2End,
                SponsorFSB3Start = c.SponsorFSB3Start,
                SponsorFSB3End = c.SponsorFSB3End,
                FirstRPHID = op.FirstRPHID,
                SecondRPHID = op.SecondRPHID
        FROM dbo.FSBTrackings ft
        INNER JOIN #Classified c
            ON c.PromotionID = ft.PromotionID
           AND c.SponsorID = ft.SponsorID
           AND c.PromoterID = ft.PromoterID
           AND c.OrderID = ft.OrderID
           AND c.FSBType = ft.FSBType
           AND c.SponsorFSB1Start = ft.SponsorFSB1Start
        LEFT JOIN #OrderPayments op
            ON op.OrderID = ft.OrderID
        WHERE ft.PromotionID = @PromotionID
          AND
          (
                ISNULL(ft.CustomerID, -1) <> ISNULL(c.CustomerID, -1)
             OR ISNULL(ft.ParticipantUserID, -1) <> ISNULL(c.ParticipantUserID, -1)
             OR ISNULL(ft.CandidateType, '') <> ISNULL(c.CandidateType, '')
             OR ISNULL(ft.SponsorFSB1End, @NullDate) <> ISNULL(c.SponsorFSB1End, @NullDate)
             OR ISNULL(ft.SponsorFSB1ExtEnd, @NullDate) <> ISNULL(c.SponsorFSB1ExtEnd, @NullDate)
             OR ISNULL(ft.SponsorFSB2Start, @NullDate) <> ISNULL(c.SponsorFSB2Start, @NullDate)
             OR ISNULL(ft.SponsorFSB2End, @NullDate) <> ISNULL(c.SponsorFSB2End, @NullDate)
             OR ISNULL(ft.SponsorFSB3Start, @NullDate) <> ISNULL(c.SponsorFSB3Start, @NullDate)
             OR ISNULL(ft.SponsorFSB3End, @NullDate) <> ISNULL(c.SponsorFSB3End, @NullDate)
             OR ISNULL(ft.FirstRPHID, -1) <> ISNULL(op.FirstRPHID, -1)
             OR ISNULL(ft.SecondRPHID, -1) <> ISNULL(op.SecondRPHID, -1)
          );

        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF XACT_STATE() <> 0
            ROLLBACK TRANSACTION;

        DECLARE @ErrorMessage NVARCHAR(4000);
        DECLARE @ErrorSeverity INT;
        DECLARE @ErrorState INT;

        SELECT
            @ErrorMessage = ERROR_MESSAGE(),
            @ErrorSeverity = ERROR_SEVERITY(),
            @ErrorState = ERROR_STATE();

        RAISERROR(@ErrorMessage, @ErrorSeverity, @ErrorState);
    END CATCH
END;
GO
