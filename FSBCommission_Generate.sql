IF OBJECT_ID('dbo.FSBCommission_Generate', 'P') IS NULL
BEGIN
    EXEC('CREATE PROCEDURE dbo.FSBCommission_Generate AS BEGIN SET NOCOUNT ON; END');
END;
GO

ALTER PROCEDURE dbo.FSBCommission_Generate
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
    DECLARE @SponsorLockResult INT;
    DECLARE @SponsorLockResource NVARCHAR(255);
    DECLARE @LockMode VARCHAR(10);
    DECLARE @OwnTransaction BIT;

    SET @OwnTransaction = CASE WHEN @@TRANCOUNT = 0 THEN 1 ELSE 0 END;
    SET @LockResource = 'FSB_Flow_' + CAST(@PromotionID AS NVARCHAR(50));
    SET @LockMode = CASE WHEN @SponsorID IS NULL THEN 'Exclusive' ELSE 'Shared' END;
    SET @SponsorLockResource = 'FSB_Flow_' + CAST(@PromotionID AS NVARCHAR(50))
                             + '_Sponsor_' + CAST(@SponsorID AS NVARCHAR(50));

    BEGIN TRY
        IF @OwnTransaction = 1
            BEGIN TRANSACTION;

        EXEC @LockResult = sys.sp_getapplock
            @Resource = @LockResource,
            @LockMode = @LockMode,
            @LockOwner = 'Transaction',
            @LockTimeout = 30000;

        IF @LockResult < 0
        BEGIN
            THROW 50000, 'Could not acquire FSB_Flow lock for FSBCommission_Generate.', 1;
        END;

        IF @SponsorID IS NOT NULL
        BEGIN
            EXEC @SponsorLockResult = sys.sp_getapplock
                @Resource = @SponsorLockResource,
                @LockMode = 'Exclusive',
                @LockOwner = 'Transaction',
                @LockTimeout = 30000;

            IF @SponsorLockResult < 0
                THROW 50000, 'Could not acquire FSB_Flow sponsor lock for FSBCommission_Generate.', 1;
        END;

        -----------------------------------------------------------------------
        -- TEMP CLEANUP
        -----------------------------------------------------------------------

        IF OBJECT_ID('tempdb..#FirstEligible') IS NOT NULL DROP TABLE #FirstEligible;
        IF OBJECT_ID('tempdb..#RenewalStatus') IS NOT NULL DROP TABLE #RenewalStatus;
        IF OBJECT_ID('tempdb..#RenewalCounts') IS NOT NULL DROP TABLE #RenewalCounts;
        IF OBJECT_ID('tempdb..#SecondEligible') IS NOT NULL DROP TABLE #SecondEligible;

        CREATE TABLE #FirstEligible
        (
            PromotionID BIGINT NOT NULL,
            SponsorID BIGINT NOT NULL,
            SponsorFSB1Start DATETIME NOT NULL,
            FSBType VARCHAR(10) NOT NULL
        );

        CREATE TABLE #SecondEligible
        (
            PromotionID BIGINT NOT NULL,
            SponsorID BIGINT NOT NULL,
            SponsorFSB1Start DATETIME NOT NULL,
            FSBType VARCHAR(10) NOT NULL
        );

        -----------------------------------------------------------------------
        -- 1. FIRST HALF ELIGIBILITY
        -----------------------------------------------------------------------

        ;WITH GroupCounts AS
        (
            SELECT
                ft.PromotionID,
                ft.SponsorID,
                ft.SponsorFSB1Start,
                ft.FSBType,
                COUNT(DISTINCT ft.PromoterID) AS PromoterCount
            FROM dbo.FSBTrackings ft
            WHERE ft.PromotionID = @PromotionID
              AND (@SponsorID IS NULL OR ft.SponsorID = @SponsorID)
              AND ft.FSBType IN ('FSB1', 'FSB1_EXT', 'FSB2', 'FSB3')
              AND ft.IsCurrent = 1
            GROUP BY
                ft.PromotionID,
                ft.SponsorID,
                ft.SponsorFSB1Start,
                ft.FSBType
        ),

        FSB1NormalEligible AS
        (
            SELECT
                PromotionID,
                SponsorID,
                SponsorFSB1Start,
                'FSB1' AS FSBType
            FROM GroupCounts
            WHERE FSBType = 'FSB1'
              AND PromoterCount >= 2
        ),

        FSB1ExtEligible AS
        (
            SELECT
                ext.PromotionID,
                ext.SponsorID,
                ext.SponsorFSB1Start,
                'FSB1' AS FSBType
            FROM GroupCounts ext
            WHERE ext.FSBType = 'FSB1_EXT'
              AND ext.PromoterCount >= 2
              AND NOT EXISTS
              (
                  SELECT 1
                  FROM FSB1NormalEligible normal
                  WHERE normal.PromotionID = ext.PromotionID
                    AND normal.SponsorID = ext.SponsorID
                    AND normal.SponsorFSB1Start = ext.SponsorFSB1Start
              )
        ),

        FSB2Eligible AS
        (
            SELECT
                f2.PromotionID,
                f2.SponsorID,
                f2.SponsorFSB1Start,
                'FSB2' AS FSBType
            FROM GroupCounts f2
            INNER JOIN FSB1NormalEligible f1
                ON f1.PromotionID = f2.PromotionID
               AND f1.SponsorID = f2.SponsorID
               AND f1.SponsorFSB1Start = f2.SponsorFSB1Start
            WHERE f2.FSBType = 'FSB2'
              AND f2.PromoterCount >= 2
        ),

        FSB3Eligible AS
        (
            SELECT
                f3.PromotionID,
                f3.SponsorID,
                f3.SponsorFSB1Start,
                'FSB3' AS FSBType
            FROM GroupCounts f3
            INNER JOIN FSB2Eligible f2
                ON f2.PromotionID = f3.PromotionID
               AND f2.SponsorID = f3.SponsorID
               AND f2.SponsorFSB1Start = f3.SponsorFSB1Start
            WHERE f3.FSBType = 'FSB3'
              AND f3.PromoterCount >= 2
        )

        INSERT INTO #FirstEligible
        (
            PromotionID,
            SponsorID,
            SponsorFSB1Start,
            FSBType
        )
        SELECT PromotionID, SponsorID, SponsorFSB1Start, FSBType FROM FSB1NormalEligible
        UNION ALL
        SELECT PromotionID, SponsorID, SponsorFSB1Start, FSBType FROM FSB1ExtEligible
        UNION ALL
        SELECT PromotionID, SponsorID, SponsorFSB1Start, FSBType FROM FSB2Eligible
        UNION ALL
        SELECT PromotionID, SponsorID, SponsorFSB1Start, FSBType FROM FSB3Eligible;

        CREATE CLUSTERED INDEX CX_FirstEligible
        ON #FirstEligible
        (
            PromotionID,
            SponsorID,
            SponsorFSB1Start,
            FSBType
        );

        -----------------------------------------------------------------------
        -- 2. INSERT FIRST HALF HEADERS
        -----------------------------------------------------------------------

        INSERT INTO dbo.FSBCommission
        (
            PromotionID,
            SponsorID,
            SponsorFSB1Start,
            FSBType,
            HalfType,
            DailyRealTimeCommissionID
        )
        SELECT DISTINCT
            fe.PromotionID,
            fe.SponsorID,
            fe.SponsorFSB1Start,
            fe.FSBType,
            'FIRST',
            NULL
        FROM #FirstEligible fe
        WHERE NOT EXISTS
        (
            SELECT 1
            FROM dbo.FSBCommission fc WITH (UPDLOCK, HOLDLOCK)
            WHERE fc.PromotionID = fe.PromotionID
              AND fc.SponsorID = fe.SponsorID
              AND fc.SponsorFSB1Start = fe.SponsorFSB1Start
              AND fc.FSBType = fe.FSBType
              AND fc.HalfType = 'FIRST'
        );

        -----------------------------------------------------------------------
        -- 3. INSERT FIRST HALF DETAILS
        --
        -- FIRST guarda todos los promoters validos del grupo.
        -----------------------------------------------------------------------

        INSERT INTO dbo.FSBCommissionDetail
        (
            FSBCommissionID,
            FSBTrackingID
        )
        SELECT
            fc.FSBCommissionID,
            ft.FSBTrackingID
        FROM dbo.FSBCommission fc
        INNER JOIN #FirstEligible fe
            ON fe.PromotionID = fc.PromotionID
           AND fe.SponsorID = fc.SponsorID
           AND fe.SponsorFSB1Start = fc.SponsorFSB1Start
           AND fe.FSBType = fc.FSBType
        INNER JOIN dbo.FSBTrackings ft
            ON ft.PromotionID = fc.PromotionID
            AND ft.SponsorID = fc.SponsorID
            AND ft.SponsorFSB1Start = fc.SponsorFSB1Start
            AND ft.IsCurrent = 1
           AND
           (
                (fc.FSBType = 'FSB1' AND ft.FSBType = 'FSB1')

             OR (fc.FSBType = 'FSB1' AND ft.FSBType = 'FSB1_EXT'
                 AND NOT EXISTS
                 (
                     SELECT 1
                     FROM dbo.FSBTrackings normal
                     WHERE normal.PromotionID = ft.PromotionID
                        AND normal.SponsorID = ft.SponsorID
                        AND normal.SponsorFSB1Start = ft.SponsorFSB1Start
                        AND normal.FSBType = 'FSB1'
                        AND normal.IsCurrent = 1
                 )
             )

             OR (fc.FSBType = 'FSB2' AND ft.FSBType = 'FSB2')
             OR (fc.FSBType = 'FSB3' AND ft.FSBType = 'FSB3')
           )
        WHERE fc.PromotionID = @PromotionID
          AND fc.HalfType = 'FIRST'
          AND (@SponsorID IS NULL OR fc.SponsorID = @SponsorID)
          AND NOT EXISTS
          (
              SELECT 1
              FROM dbo.FSBCommissionDetail d WITH (UPDLOCK, HOLDLOCK)
              WHERE d.FSBCommissionID = fc.FSBCommissionID
                AND d.FSBTrackingID = ft.FSBTrackingID
          );

        -----------------------------------------------------------------------
        -- 4. VALID RENEWAL STATUS
        --
        -- Regla actual:
        -- Renewal valido si FirstRPHID o SecondRPHID tiene CreateDate
        -- entre 1 y 44 dias desde OrderDate.
        --
        -- IMPORTANTE:
        -- Se usa RecurringPaymentsHistory.CreateDate.
        -- NO se usa PaymentMade.
        -----------------------------------------------------------------------

        CREATE TABLE #RenewalStatus
        (
            FSBTrackingID BIGINT NOT NULL,
            PromoterID BIGINT NOT NULL,
            ValidRenewalRPHID BIGINT NULL,
            ValidRenewalCreateDate DATETIME NULL,
            HasValidRenewal BIT NOT NULL
        );

        INSERT INTO #RenewalStatus
        (
            FSBTrackingID,
            PromoterID,
            ValidRenewalRPHID,
            ValidRenewalCreateDate,
            HasValidRenewal
        )
        SELECT
            ft.FSBTrackingID,
            ft.PromoterID,

            CASE
                WHEN rphFirst.ID IS NOT NULL
                 AND DATEDIFF(DAY, o.OrderDate, rphFirst.CreateDate) BETWEEN 1 AND 44
                    THEN rphFirst.ID

                WHEN rphSecond.ID IS NOT NULL
                 AND DATEDIFF(DAY, o.OrderDate, rphSecond.CreateDate) BETWEEN 1 AND 44
                    THEN rphSecond.ID

                ELSE NULL
            END AS ValidRenewalRPHID,

            CASE
                WHEN rphFirst.ID IS NOT NULL
                 AND DATEDIFF(DAY, o.OrderDate, rphFirst.CreateDate) BETWEEN 1 AND 44
                    THEN rphFirst.CreateDate

                WHEN rphSecond.ID IS NOT NULL
                 AND DATEDIFF(DAY, o.OrderDate, rphSecond.CreateDate) BETWEEN 1 AND 44
                    THEN rphSecond.CreateDate

                ELSE NULL
            END AS ValidRenewalCreateDate,

            CASE
                WHEN rphFirst.ID IS NOT NULL
                 AND DATEDIFF(DAY, o.OrderDate, rphFirst.CreateDate) BETWEEN 1 AND 44
                    THEN 1

                WHEN rphSecond.ID IS NOT NULL
                 AND DATEDIFF(DAY, o.OrderDate, rphSecond.CreateDate) BETWEEN 1 AND 44
                    THEN 1

                ELSE 0
            END AS HasValidRenewal

        FROM dbo.FSBTrackings ft
        INNER JOIN dbo.[Order] o
            ON o.OrderID = ft.OrderID

        LEFT JOIN dbo.RecurringPaymentsHistory rphFirst
            ON rphFirst.ID = ft.FirstRPHID
           AND rphFirst.Status = 'SUCCESS'
           AND ISNULL(rphFirst.Reverted, 0) = 0

        LEFT JOIN dbo.RecurringPaymentsHistory rphSecond
            ON rphSecond.ID = ft.SecondRPHID
           AND rphSecond.Status = 'SUCCESS'
           AND ISNULL(rphSecond.Reverted, 0) = 0

        WHERE ft.PromotionID = @PromotionID
          AND (@SponsorID IS NULL OR ft.SponsorID = @SponsorID)
          AND ft.FSBType IN ('FSB1', 'FSB1_EXT', 'FSB2', 'FSB3');

        CREATE UNIQUE CLUSTERED INDEX CX_RenewalStatus
        ON #RenewalStatus (FSBTrackingID);

        CREATE INDEX IX_RenewalStatus_HasValidRenewal
        ON #RenewalStatus
        (
            HasValidRenewal,
            FSBTrackingID
        );

        -----------------------------------------------------------------------
        -- 5. RENEWAL COUNTS BY FIRST COMMISSION GROUP
        --
        -- Se cuenta por grupo de FIRST HALF:
        -- FSB1, FSB2, FSB3.
        -----------------------------------------------------------------------

        CREATE TABLE #RenewalCounts
        (
            PromotionID BIGINT NOT NULL,
            SponsorID BIGINT NOT NULL,
            SponsorFSB1Start DATETIME NOT NULL,
            FSBGroup VARCHAR(10) NOT NULL,
            RenewedCount INT NOT NULL
        );

        INSERT INTO #RenewalCounts
        (
            PromotionID,
            SponsorID,
            SponsorFSB1Start,
            FSBGroup,
            RenewedCount
        )
        SELECT
            firstFc.PromotionID,
            firstFc.SponsorID,
            firstFc.SponsorFSB1Start,
            firstFc.FSBType AS FSBGroup,
            COUNT(DISTINCT rs.PromoterID) AS RenewedCount
        FROM dbo.FSBCommission firstFc
        INNER JOIN dbo.FSBCommissionDetail d
            ON d.FSBCommissionID = firstFc.FSBCommissionID
        INNER JOIN #RenewalStatus rs
            ON rs.FSBTrackingID = d.FSBTrackingID
           AND rs.HasValidRenewal = 1
        WHERE firstFc.PromotionID = @PromotionID
          AND firstFc.HalfType = 'FIRST'
          AND (@SponsorID IS NULL OR firstFc.SponsorID = @SponsorID)
        GROUP BY
            firstFc.PromotionID,
            firstFc.SponsorID,
            firstFc.SponsorFSB1Start,
            firstFc.FSBType;

        CREATE CLUSTERED INDEX CX_RenewalCounts
        ON #RenewalCounts
        (
            PromotionID,
            SponsorID,
            SponsorFSB1Start,
            FSBGroup
        );

        -----------------------------------------------------------------------
        -- 6. SECOND HALF ELIGIBILITY
        -----------------------------------------------------------------------

        -- FSB1 SECOND:
        -- minimo 2 renewals validos del grupo FSB1.
        INSERT INTO #SecondEligible
        (
            PromotionID,
            SponsorID,
            SponsorFSB1Start,
            FSBType
        )
        SELECT DISTINCT
            rc.PromotionID,
            rc.SponsorID,
            rc.SponsorFSB1Start,
            'FSB1' AS FSBType
        FROM #RenewalCounts rc
        INNER JOIN dbo.FSBCommission firstFc
            ON firstFc.PromotionID = rc.PromotionID
           AND firstFc.SponsorID = rc.SponsorID
           AND firstFc.SponsorFSB1Start = rc.SponsorFSB1Start
           AND firstFc.FSBType = 'FSB1'
           AND firstFc.HalfType = 'FIRST'
        WHERE rc.FSBGroup = 'FSB1'
          AND rc.RenewedCount >= 2;

        -- FSB2 SECOND:
        -- minimo 2 renewals FSB1 + minimo 2 renewals FSB2.
        INSERT INTO #SecondEligible
        (
            PromotionID,
            SponsorID,
            SponsorFSB1Start,
            FSBType
        )
        SELECT DISTINCT
            f1.PromotionID,
            f1.SponsorID,
            f1.SponsorFSB1Start,
            'FSB2' AS FSBType
        FROM #RenewalCounts f1
        INNER JOIN #RenewalCounts f2
            ON f2.PromotionID = f1.PromotionID
           AND f2.SponsorID = f1.SponsorID
           AND f2.SponsorFSB1Start = f1.SponsorFSB1Start
           AND f2.FSBGroup = 'FSB2'
        INNER JOIN dbo.FSBCommission firstFc
            ON firstFc.PromotionID = f1.PromotionID
           AND firstFc.SponsorID = f1.SponsorID
           AND firstFc.SponsorFSB1Start = f1.SponsorFSB1Start
           AND firstFc.FSBType = 'FSB2'
           AND firstFc.HalfType = 'FIRST'
        WHERE f1.FSBGroup = 'FSB1'
          AND f1.RenewedCount >= 2
          AND f2.RenewedCount >= 2;

        -- FSB3 SECOND:
        -- minimo 2 renewals FSB1 + minimo 2 renewals FSB2 + minimo 2 renewals FSB3.
        INSERT INTO #SecondEligible
        (
            PromotionID,
            SponsorID,
            SponsorFSB1Start,
            FSBType
        )
        SELECT DISTINCT
            f1.PromotionID,
            f1.SponsorID,
            f1.SponsorFSB1Start,
            'FSB3' AS FSBType
        FROM #RenewalCounts f1
        INNER JOIN #RenewalCounts f2
            ON f2.PromotionID = f1.PromotionID
           AND f2.SponsorID = f1.SponsorID
           AND f2.SponsorFSB1Start = f1.SponsorFSB1Start
           AND f2.FSBGroup = 'FSB2'
        INNER JOIN #RenewalCounts f3
            ON f3.PromotionID = f1.PromotionID
           AND f3.SponsorID = f1.SponsorID
           AND f3.SponsorFSB1Start = f1.SponsorFSB1Start
           AND f3.FSBGroup = 'FSB3'
        INNER JOIN dbo.FSBCommission firstFc
            ON firstFc.PromotionID = f1.PromotionID
           AND firstFc.SponsorID = f1.SponsorID
           AND firstFc.SponsorFSB1Start = f1.SponsorFSB1Start
           AND firstFc.FSBType = 'FSB3'
           AND firstFc.HalfType = 'FIRST'
        WHERE f1.FSBGroup = 'FSB1'
          AND f1.RenewedCount >= 2
          AND f2.RenewedCount >= 2
          AND f3.RenewedCount >= 2;

        CREATE CLUSTERED INDEX CX_SecondEligible
        ON #SecondEligible
        (
            PromotionID,
            SponsorID,
            SponsorFSB1Start,
            FSBType
        );

        -----------------------------------------------------------------------
        -- 7. INSERT SECOND HALF HEADERS
        -----------------------------------------------------------------------

        INSERT INTO dbo.FSBCommission
        (
            PromotionID,
            SponsorID,
            SponsorFSB1Start,
            FSBType,
            HalfType,
            DailyRealTimeCommissionID
        )
        SELECT DISTINCT
            se.PromotionID,
            se.SponsorID,
            se.SponsorFSB1Start,
            se.FSBType,
            'SECOND',
            NULL
        FROM #SecondEligible se
        WHERE NOT EXISTS
        (
            SELECT 1
            FROM dbo.FSBCommission fc WITH (UPDLOCK, HOLDLOCK)
            WHERE fc.PromotionID = se.PromotionID
              AND fc.SponsorID = se.SponsorID
              AND fc.SponsorFSB1Start = se.SponsorFSB1Start
              AND fc.FSBType = se.FSBType
              AND fc.HalfType = 'SECOND'
        );

        -----------------------------------------------------------------------
        -- 8. INSERT SECOND HALF DETAILS
        --
        -- SECOND guarda solo los promoters con renewal valido.
        --
        -- FSB1 SECOND:
        --     detalles renovados de FSB1.
        --
        -- FSB2 SECOND:
        --     detalles renovados de FSB1 + FSB2.
        --
        -- FSB3 SECOND:
        --     detalles renovados de FSB1 + FSB2 + FSB3.
        -----------------------------------------------------------------------

        INSERT INTO dbo.FSBCommissionDetail
        (
            FSBCommissionID,
            FSBTrackingID
        )
        SELECT
            secondFc.FSBCommissionID,
            d.FSBTrackingID
        FROM dbo.FSBCommission secondFc
        INNER JOIN #SecondEligible se
            ON se.PromotionID = secondFc.PromotionID
           AND se.SponsorID = secondFc.SponsorID
           AND se.SponsorFSB1Start = secondFc.SponsorFSB1Start
           AND se.FSBType = secondFc.FSBType

        INNER JOIN dbo.FSBCommission firstFc
            ON firstFc.PromotionID = secondFc.PromotionID
           AND firstFc.SponsorID = secondFc.SponsorID
           AND firstFc.SponsorFSB1Start = secondFc.SponsorFSB1Start
           AND firstFc.HalfType = 'FIRST'
           AND
           (
                (secondFc.FSBType = 'FSB1' AND firstFc.FSBType = 'FSB1')
             OR (secondFc.FSBType = 'FSB2' AND firstFc.FSBType IN ('FSB1', 'FSB2'))
             OR (secondFc.FSBType = 'FSB3' AND firstFc.FSBType IN ('FSB1', 'FSB2', 'FSB3'))
           )

        INNER JOIN dbo.FSBCommissionDetail d
            ON d.FSBCommissionID = firstFc.FSBCommissionID

        INNER JOIN #RenewalStatus rs
            ON rs.FSBTrackingID = d.FSBTrackingID
           AND rs.HasValidRenewal = 1

        WHERE secondFc.PromotionID = @PromotionID
          AND secondFc.HalfType = 'SECOND'
          AND (@SponsorID IS NULL OR secondFc.SponsorID = @SponsorID)
          AND NOT EXISTS
          (
              SELECT 1
              FROM dbo.FSBCommissionDetail existing WITH (UPDLOCK, HOLDLOCK)
              WHERE existing.FSBCommissionID = secondFc.FSBCommissionID
                AND existing.FSBTrackingID = d.FSBTrackingID
          );

        IF @OwnTransaction = 1
            COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @OwnTransaction = 1 AND XACT_STATE() <> 0
            ROLLBACK TRANSACTION;

        DECLARE @ErrorMessage NVARCHAR(4000);
        DECLARE @ErrorSeverity INT;
        DECLARE @ErrorState INT;

        SELECT
            @ErrorMessage = ERROR_MESSAGE(),
            @ErrorSeverity = ERROR_SEVERITY(),
            @ErrorState = ERROR_STATE();

        IF @OwnTransaction = 1
            RAISERROR(@ErrorMessage, @ErrorSeverity, @ErrorState);
        ELSE
            THROW;
    END CATCH
END;
GO
