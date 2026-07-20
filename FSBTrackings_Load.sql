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

    DECLARE @PromotionStartDate DATETIME;
    DECLARE @PromotionEndDate DATETIME;

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

        SELECT
            @PromotionStartDate = StartDate,
            @PromotionEndDate = EndDate
        FROM dbo.Promotions WITH (UPDLOCK, HOLDLOCK)
        WHERE PromotionID = @PromotionID;

        IF @PromotionStartDate IS NULL OR @PromotionEndDate IS NULL
        BEGIN
            RAISERROR('Invalid PromotionID.', 16, 1);
            ROLLBACK TRANSACTION;
            RETURN;
        END;

        -----------------------------------------------------------------------
        -- TEMP CLEANUP
        -----------------------------------------------------------------------

        IF OBJECT_ID('tempdb..#BaseOrders') IS NOT NULL DROP TABLE #BaseOrders;
        IF OBJECT_ID('tempdb..#FSB1WindowRows') IS NOT NULL DROP TABLE #FSB1WindowRows;
        IF OBJECT_ID('tempdb..#FSB1Qualified') IS NOT NULL DROP TABLE #FSB1Qualified;
        IF OBJECT_ID('tempdb..#FSB1NormalRows') IS NOT NULL DROP TABLE #FSB1NormalRows;
        IF OBJECT_ID('tempdb..#FSB1ExtRows') IS NOT NULL DROP TABLE #FSB1ExtRows;
        IF OBJECT_ID('tempdb..#FSB2Candidates') IS NOT NULL DROP TABLE #FSB2Candidates;
        IF OBJECT_ID('tempdb..#FSB2Qualified') IS NOT NULL DROP TABLE #FSB2Qualified;
        IF OBJECT_ID('tempdb..#FSB3Candidates') IS NOT NULL DROP TABLE #FSB3Candidates;
        IF OBJECT_ID('tempdb..#Classified') IS NOT NULL DROP TABLE #Classified;
        IF OBJECT_ID('tempdb..#OrderIDs') IS NOT NULL DROP TABLE #OrderIDs;
        IF OBJECT_ID('tempdb..#OrderPayments') IS NOT NULL DROP TABLE #OrderPayments;

        -----------------------------------------------------------------------
        -- 1. BASE ORDERS
        -- Una sola orden válida por promoter dentro del ciclo.
        -----------------------------------------------------------------------

        CREATE TABLE #BaseOrders
        (
            PromotionID BIGINT NOT NULL,
            SponsorID BIGINT NOT NULL,
            PromoterID BIGINT NOT NULL,
            OrderID BIGINT NOT NULL,
            OrderDate DATETIME NOT NULL,

            SponsorFSB1Start DATETIME NOT NULL,
            SponsorFSB1End DATETIME NOT NULL,
            SponsorFSB1ExtEnd DATETIME NOT NULL,

            SponsorFSB2Start DATETIME NULL,
            SponsorFSB2End DATETIME NULL,

            SponsorFSB3Start DATETIME NULL,
            SponsorFSB3End DATETIME NULL
        );

        ;WITH RawOrders AS
        (
            SELECT
                @PromotionID AS PromotionID,

                sponsor.PromoterID AS SponsorID,
                child.PromoterID AS PromoterID,

                o.OrderID,
                o.OrderDate,

                sponsor.FSB1StartDate AS SponsorFSB1Start,
                sponsor.FSB1EndDate AS SponsorFSB1End,
                DATEADD(DAY, 7, sponsor.FSB1EndDate) AS SponsorFSB1ExtEnd,

                sponsor.FSB2StartDate AS SponsorFSB2Start,
                sponsor.FSB2EndDate AS SponsorFSB2End,

                sponsor.FSB3StartDate AS SponsorFSB3Start,
                sponsor.FSB3EndDate AS SponsorFSB3End,

                ROW_NUMBER() OVER
                (
                    PARTITION BY
                        sponsor.PromoterID,
                        child.PromoterID,
                        sponsor.FSB1StartDate
                    ORDER BY
                        o.OrderDate,
                        o.OrderID
                ) AS rn
            FROM dbo.Promoters child
            INNER JOIN dbo.Promoters sponsor
                ON sponsor.PromoterID = child.SponsorID
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

              -- No usar EnrollDate. Todo es OrderDate.
              AND sponsor.FSB1StartDate IS NOT NULL
              AND sponsor.FSB1EndDate IS NOT NULL
              AND o.OrderDate >= sponsor.FSB1StartDate

              -- Reduce universo de búsqueda.
              AND o.OrderDate <= DATEADD(DAY, 21, sponsor.FSB1StartDate)

              AND (@SponsorID IS NULL OR sponsor.PromoterID = @SponsorID)
        )
        INSERT INTO #BaseOrders
        (
            PromotionID,
            SponsorID,
            PromoterID,
            OrderID,
            OrderDate,

            SponsorFSB1Start,
            SponsorFSB1End,
            SponsorFSB1ExtEnd,

            SponsorFSB2Start,
            SponsorFSB2End,

            SponsorFSB3Start,
            SponsorFSB3End
        )
        SELECT
            PromotionID,
            SponsorID,
            PromoterID,
            OrderID,
            OrderDate,

            SponsorFSB1Start,
            SponsorFSB1End,
            SponsorFSB1ExtEnd,

            SponsorFSB2Start,
            SponsorFSB2End,

            SponsorFSB3Start,
            SponsorFSB3End
        FROM RawOrders
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
            OrderDate
        );

        -----------------------------------------------------------------------
        -- 2. FSB1 NORMAL
        -----------------------------------------------------------------------

        SELECT *
        INTO #FSB1WindowRows
        FROM #BaseOrders
        WHERE OrderDate >= SponsorFSB1Start
          AND OrderDate <= SponsorFSB1End;

        CREATE CLUSTERED INDEX CX_FSB1WindowRows
        ON #FSB1WindowRows
        (
            PromotionID,
            SponsorID,
            SponsorFSB1Start,
            PromoterID
        );

        SELECT
            PromotionID,
            SponsorID,
            SponsorFSB1Start
        INTO #FSB1Qualified
        FROM #FSB1WindowRows
        GROUP BY
            PromotionID,
            SponsorID,
            SponsorFSB1Start
        HAVING COUNT(DISTINCT PromoterID) >= 2;

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
           AND q.SponsorFSB1Start = f1.SponsorFSB1Start;

        CREATE CLUSTERED INDEX CX_FSB1NormalRows
        ON #FSB1NormalRows
        (
            PromotionID,
            SponsorID,
            SponsorFSB1Start,
            PromoterID
        );

        -----------------------------------------------------------------------
        -- 3. FSB1 EXT
        -- Si no logró FSB1 normal, todos los promoters desde FSB1Start
        -- hasta SponsorFSB1ExtEnd forman el grupo FSB1_EXT.
        -----------------------------------------------------------------------

        SELECT b.*
        INTO #FSB1ExtRows
        FROM #BaseOrders b
        WHERE b.OrderDate >= b.SponsorFSB1Start
          AND b.OrderDate <= b.SponsorFSB1ExtEnd
          AND NOT EXISTS
          (
              SELECT 1
              FROM #FSB1Qualified q
              WHERE q.PromotionID = b.PromotionID
                AND q.SponsorID = b.SponsorID
                AND q.SponsorFSB1Start = b.SponsorFSB1Start
          );

        CREATE CLUSTERED INDEX CX_FSB1ExtRows
        ON #FSB1ExtRows
        (
            PromotionID,
            SponsorID,
            SponsorFSB1Start,
            PromoterID
        );

        -----------------------------------------------------------------------
        -- 4. FSB2
        -- Solo si FSB1 normal fue logrado.
        -- El promoter no puede haber contado en FSB1/EXT.
        -----------------------------------------------------------------------

        SELECT b.*
        INTO #FSB2Candidates
        FROM #BaseOrders b
        INNER JOIN #FSB1Qualified q
            ON q.PromotionID = b.PromotionID
           AND q.SponsorID = b.SponsorID
           AND q.SponsorFSB1Start = b.SponsorFSB1Start
        WHERE b.SponsorFSB2Start IS NOT NULL
          AND b.SponsorFSB2End IS NOT NULL
          AND b.OrderDate >= b.SponsorFSB2Start
          AND b.OrderDate <= b.SponsorFSB2End

          AND NOT EXISTS
          (
              SELECT 1
              FROM #FSB1NormalRows f1
              WHERE f1.PromotionID = b.PromotionID
                AND f1.SponsorID = b.SponsorID
                AND f1.SponsorFSB1Start = b.SponsorFSB1Start
                AND f1.PromoterID = b.PromoterID
          )

          AND NOT EXISTS
          (
              SELECT 1
              FROM #FSB1ExtRows ext
              WHERE ext.PromotionID = b.PromotionID
                AND ext.SponsorID = b.SponsorID
                AND ext.SponsorFSB1Start = b.SponsorFSB1Start
                AND ext.PromoterID = b.PromoterID
          );

        CREATE CLUSTERED INDEX CX_FSB2Candidates
        ON #FSB2Candidates
        (
            PromotionID,
            SponsorID,
            SponsorFSB1Start,
            PromoterID
        );

        SELECT
            PromotionID,
            SponsorID,
            SponsorFSB1Start
        INTO #FSB2Qualified
        FROM #FSB2Candidates
        GROUP BY
            PromotionID,
            SponsorID,
            SponsorFSB1Start
        HAVING COUNT(DISTINCT PromoterID) >= 2;

        CREATE UNIQUE CLUSTERED INDEX CX_FSB2Qualified
        ON #FSB2Qualified
        (
            PromotionID,
            SponsorID,
            SponsorFSB1Start
        );

        -----------------------------------------------------------------------
        -- 5. FSB3
        -- Solo si FSB2 fue logrado.
        -- El promoter no puede haber contado en FSB1/EXT/FSB2.
        -----------------------------------------------------------------------

        SELECT b.*
        INTO #FSB3Candidates
        FROM #BaseOrders b
        INNER JOIN #FSB2Qualified q
            ON q.PromotionID = b.PromotionID
           AND q.SponsorID = b.SponsorID
           AND q.SponsorFSB1Start = b.SponsorFSB1Start
        WHERE b.SponsorFSB3Start IS NOT NULL
          AND b.SponsorFSB3End IS NOT NULL
          AND b.OrderDate >= b.SponsorFSB3Start
          AND b.OrderDate <= b.SponsorFSB3End

          AND NOT EXISTS
          (
              SELECT 1
              FROM #FSB1NormalRows f1
              WHERE f1.PromotionID = b.PromotionID
                AND f1.SponsorID = b.SponsorID
                AND f1.SponsorFSB1Start = b.SponsorFSB1Start
                AND f1.PromoterID = b.PromoterID
          )

          AND NOT EXISTS
          (
              SELECT 1
              FROM #FSB1ExtRows ext
              WHERE ext.PromotionID = b.PromotionID
                AND ext.SponsorID = b.SponsorID
                AND ext.SponsorFSB1Start = b.SponsorFSB1Start
                AND ext.PromoterID = b.PromoterID
          )

          AND NOT EXISTS
          (
              SELECT 1
              FROM #FSB2Candidates f2
              WHERE f2.PromotionID = b.PromotionID
                AND f2.SponsorID = b.SponsorID
                AND f2.SponsorFSB1Start = b.SponsorFSB1Start
                AND f2.PromoterID = b.PromoterID
          );

        CREATE CLUSTERED INDEX CX_FSB3Candidates
        ON #FSB3Candidates
        (
            PromotionID,
            SponsorID,
            SponsorFSB1Start,
            PromoterID
        );

        -----------------------------------------------------------------------
        -- 6. CLASSIFIED
        -----------------------------------------------------------------------

        CREATE TABLE #Classified
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

        INSERT INTO #Classified
        SELECT
            PromotionID,
            SponsorID,
            PromoterID,
            OrderID,
            OrderDate,
            'FSB1',
            SponsorFSB1Start,
            SponsorFSB1End,
            SponsorFSB1ExtEnd,
            SponsorFSB2Start,
            SponsorFSB2End,
            SponsorFSB3Start,
            SponsorFSB3End
        FROM #FSB1NormalRows;

        INSERT INTO #Classified
        SELECT
            PromotionID,
            SponsorID,
            PromoterID,
            OrderID,
            OrderDate,
            'FSB1_EXT',
            SponsorFSB1Start,
            SponsorFSB1End,
            SponsorFSB1ExtEnd,
            SponsorFSB2Start,
            SponsorFSB2End,
            SponsorFSB3Start,
            SponsorFSB3End
        FROM #FSB1ExtRows;

        INSERT INTO #Classified
        SELECT
            PromotionID,
            SponsorID,
            PromoterID,
            OrderID,
            OrderDate,
            'FSB2',
            SponsorFSB1Start,
            SponsorFSB1End,
            SponsorFSB1ExtEnd,
            SponsorFSB2Start,
            SponsorFSB2End,
            SponsorFSB3Start,
            SponsorFSB3End
        FROM #FSB2Candidates;

        INSERT INTO #Classified
        SELECT
            PromotionID,
            SponsorID,
            PromoterID,
            OrderID,
            OrderDate,
            'FSB3',
            SponsorFSB1Start,
            SponsorFSB1End,
            SponsorFSB1ExtEnd,
            SponsorFSB2Start,
            SponsorFSB2End,
            SponsorFSB3Start,
            SponsorFSB3End
        FROM #FSB3Candidates;

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

        -----------------------------------------------------------------------
        -- 7. PAYMENTS
        -- Buscar RPH solo una vez por OrderID.
        -- FirstRPHID = primer SUCCESS por CreateDate.
        -- SecondRPHID = segundo SUCCESS por CreateDate.
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
            OrderID,
            MAX(CASE WHEN PaymentRank = 1 THEN ID END) AS FirstRPHID,
            MAX(CASE WHEN PaymentRank = 2 THEN ID END) AS SecondRPHID
        INTO #OrderPayments
        FROM RankedPayments
        WHERE PaymentRank IN (1, 2)
        GROUP BY OrderID;

        CREATE UNIQUE CLUSTERED INDEX CX_OrderPayments
        ON #OrderPayments (OrderID);

        -----------------------------------------------------------------------
        -- 8. INSERT TRACKINGS
        -----------------------------------------------------------------------

        INSERT INTO dbo.FSBTrackings
        (
            PromotionID,
            SponsorID,
            PromoterID,
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
        -- 9. UPDATE EXISTING TRACKINGS WITH CURRENT FIRST/SECOND PAYMENT
        -----------------------------------------------------------------------

        UPDATE ft
            SET
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
                ISNULL(ft.FirstRPHID, -1) <> ISNULL(op.FirstRPHID, -1)
             OR ISNULL(ft.SecondRPHID, -1) <> ISNULL(op.SecondRPHID, -1)
          );

        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0
            ROLLBACK TRANSACTION;

        DECLARE @ErrorMessage NVARCHAR(4000);
        DECLARE @ErrorSeverity INT;
        DECLARE @ErrorState INT;

        SELECT
            @ErrorMessage = ERROR_MESSAGE(),
            @ErrorSeverity = ERROR_SEVERITY(),
            @ErrorState = ERROR_STATE();

        RAISERROR(@ErrorMessage, @ErrorSeverity, @ErrorState);
        RETURN;
    END CATCH
END;
GO