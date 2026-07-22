IF OBJECT_ID('dbo.FSBCommission_TrackingReport', 'P') IS NULL
BEGIN
    EXEC('CREATE PROCEDURE dbo.FSBCommission_TrackingReport AS BEGIN SET NOCOUNT ON; END');
END;
GO

ALTER PROCEDURE dbo.FSBCommission_TrackingReport
(
    @SponsorID BIGINT = NULL,
    @ShowAllColumns BIT = NULL
)
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @EffectivePromotionID BIGINT;

    BEGIN TRY

        -----------------------------------------------------------------------
        -- 1. RESOLVE CURRENT ACTIVE FSB PROMOTION
        -----------------------------------------------------------------------

        SELECT TOP (1)
            @EffectivePromotionID = p.PromotionID
        FROM dbo.Promotions p
        WHERE p.Type = 'FSB'
          AND GETDATE() >= p.StartDate
          AND GETDATE() <= p.EndDate
        ORDER BY
            p.StartDate DESC,
            p.PromotionID DESC;

        IF @EffectivePromotionID IS NULL OR @EffectivePromotionID = 0
        BEGIN
            RAISERROR('No active FSB promotion was found.', 16, 1);
            RETURN;
        END;

        -----------------------------------------------------------------------
        -- 2. AUTO REFRESH ONLY FOR SPECIFIC SPONSOR
        -----------------------------------------------------------------------

        IF @SponsorID IS NOT NULL
        BEGIN
            EXEC dbo.FSBTrackings_Load
                @PromotionID = @EffectivePromotionID,
                @SponsorID = @SponsorID;

            EXEC dbo.FSBCommission_Generate
                @PromotionID = @EffectivePromotionID,
                @SponsorID = @SponsorID;
        END;

        -----------------------------------------------------------------------
        -- 3. BUILD TRACKING SCREEN ROWS
        --
        -- Base = FIRST commission rows only.
        -- SECOND information is joined into the FIRST row.
        -- This avoids duplicate FIRST / SECOND rows in the UI.
        -----------------------------------------------------------------------

        IF OBJECT_ID('tempdb..#ScreenRows') IS NOT NULL
            DROP TABLE #ScreenRows;

        ;WITH FirstRows AS
        (
            SELECT
                firstFc.FSBCommissionID AS FirstFSBCommissionID,
                firstFc.CreatedAt AS FirstCommissionCreatedAt,

                firstFc.PromotionID,
                firstFc.SponsorID,
                firstFc.SponsorFSB1Start,

                firstFc.FSBType AS CommissionFSBType,
                firstFc.HalfType AS FirstHalfType,

                ft.FSBTrackingID,
                ft.FSBType AS TrackingFSBType,

                ft.PromoterID,
                promoter.UserProfileID,
                promoter.EnrollDate AS PromoterEnrollDate,

                ft.OrderID,
                o.OrderDate,
                o.[Status] AS OrderStatus,
                o.ProductID,

                ft.FirstRPHID,
                rphFirst.CreateDate AS FirstRPHCreateDate,
                DATEDIFF(DAY, o.OrderDate, rphFirst.CreateDate) AS FirstRPHDays,

                ft.SecondRPHID,
                rphSecond.CreateDate AS SecondRPHCreateDate,
                DATEDIFF(DAY, o.OrderDate, rphSecond.CreateDate) AS SecondRPHDays,

                lastSuccessfulRph.LastSuccessfulRPHCreateDate,
                ISNULL(lastSuccessfulRph.SuccessfulRPHCount, 0) AS SuccessfulRecurringPaymentsHistoryCount,

                rp.[NextPaymentDate] AS RecurringPaymentNextPaymentDate,
                rp.[PaymentCount] AS RecurringPaymentCount,

                ft.SponsorFSB1Start AS FSB1StartDate,
                ft.SponsorFSB1End AS FSB1EndDate,

                ft.SponsorFSB1End AS FSB1ExtStartDate,
                ft.SponsorFSB1ExtEnd AS FSB1ExtEndDate,

                ft.SponsorFSB2Start AS FSB2StartDate,
                ft.SponsorFSB2End AS FSB2EndDate,

                ft.SponsorFSB3Start AS FSB3StartDate,
                ft.SponsorFSB3End AS FSB3EndDate,

                up.UserName,
                up.FirstName,
                up.LastName,

                prod.[Name] AS ProductName

            FROM dbo.FSBCommission firstFc

            INNER JOIN dbo.FSBCommissionDetail firstDetail
                ON firstDetail.FSBCommissionID = firstFc.FSBCommissionID

            INNER JOIN dbo.FSBTrackings ft
                ON ft.FSBTrackingID = firstDetail.FSBTrackingID

            INNER JOIN dbo.[Order] o
                ON o.OrderID = ft.OrderID

            INNER JOIN dbo.Promoters promoter
                ON promoter.PromoterID = ft.PromoterID

            LEFT JOIN dbo.UserProfile up
                ON up.UserID = promoter.UserProfileID

            LEFT JOIN dbo.Product prod
                ON prod.ProductID = o.ProductID

            LEFT JOIN dbo.RecurringPaymentsHistory rphFirst
                ON rphFirst.ID = ft.FirstRPHID
               AND rphFirst.Status = 'SUCCESS'
               AND ISNULL(rphFirst.Reverted, 0) = 0

            LEFT JOIN dbo.RecurringPaymentsHistory rphSecond
                ON rphSecond.ID = ft.SecondRPHID
               AND rphSecond.Status = 'SUCCESS'
               AND ISNULL(rphSecond.Reverted, 0) = 0

            OUTER APPLY
            (
                SELECT
                    MAX(rph.CreateDate) AS LastSuccessfulRPHCreateDate,
                    COUNT(1) AS SuccessfulRPHCount
                FROM dbo.RecurringPaymentsHistory rph
                WHERE rph.OrderId = ft.OrderID
                  AND rph.[Status] = 'SUCCESS'
                  AND ISNULL(rph.Reverted, 0) = 0
            ) lastSuccessfulRph

            LEFT JOIN dbo.RecurringPayments rp
                ON rp.[OrderId] = ft.OrderID

            WHERE firstFc.PromotionID = @EffectivePromotionID
              AND firstFc.HalfType = 'FIRST'
              AND (@SponsorID IS NULL OR firstFc.SponsorID = @SponsorID)
        ),

        RenewalEval AS
        (
            SELECT
                fr.*,

                CASE
                    WHEN fr.FirstRPHID IS NOT NULL
                     AND DATEDIFF(DAY, fr.OrderDate, fr.FirstRPHCreateDate) BETWEEN 1 AND 44
                        THEN fr.FirstRPHID

                    WHEN fr.SecondRPHID IS NOT NULL
                     AND DATEDIFF(DAY, fr.OrderDate, fr.SecondRPHCreateDate) BETWEEN 1 AND 44
                        THEN fr.SecondRPHID

                    ELSE NULL
                END AS ValidRenewalRPHID,

                CASE
                    WHEN fr.FirstRPHID IS NOT NULL
                     AND DATEDIFF(DAY, fr.OrderDate, fr.FirstRPHCreateDate) BETWEEN 1 AND 44
                        THEN fr.FirstRPHCreateDate

                    WHEN fr.SecondRPHID IS NOT NULL
                     AND DATEDIFF(DAY, fr.OrderDate, fr.SecondRPHCreateDate) BETWEEN 1 AND 44
                        THEN fr.SecondRPHCreateDate

                    ELSE NULL
                END AS ValidRenewalCreateDate,

                CASE
                    WHEN fr.FirstRPHID IS NOT NULL
                     AND DATEDIFF(DAY, fr.OrderDate, fr.FirstRPHCreateDate) BETWEEN 1 AND 44
                        THEN 'FirstRPHID'

                    WHEN fr.SecondRPHID IS NOT NULL
                     AND DATEDIFF(DAY, fr.OrderDate, fr.SecondRPHCreateDate) BETWEEN 1 AND 44
                        THEN 'SecondRPHID'

                    ELSE NULL
                END AS ValidRenewalSource,

                CASE
                    WHEN fr.FirstRPHID IS NOT NULL
                     AND DATEDIFF(DAY, fr.OrderDate, fr.FirstRPHCreateDate) BETWEEN 1 AND 44
                        THEN DATEDIFF(DAY, fr.OrderDate, fr.FirstRPHCreateDate)

                    WHEN fr.SecondRPHID IS NOT NULL
                     AND DATEDIFF(DAY, fr.OrderDate, fr.SecondRPHCreateDate) BETWEEN 1 AND 44
                        THEN DATEDIFF(DAY, fr.OrderDate, fr.SecondRPHCreateDate)

                    ELSE NULL
                END AS RenewalDaysFromOrderDate
            FROM FirstRows fr
        ),

        ScreenRows AS
        (
            SELECT
                re.*,

                secondFc.FSBCommissionID AS SecondFSBCommissionID,
                secondFc.CreatedAt AS SecondCommissionCreatedAt,

                secondDetail.FSBCommissionDetailID AS SecondFSBCommissionDetailID

            FROM RenewalEval re

            LEFT JOIN dbo.FSBCommission secondFc
                ON secondFc.PromotionID = re.PromotionID
               AND secondFc.SponsorID = re.SponsorID
               AND secondFc.SponsorFSB1Start = re.SponsorFSB1Start
               AND secondFc.FSBType = re.CommissionFSBType
               AND secondFc.HalfType = 'SECOND'

            LEFT JOIN dbo.FSBCommissionDetail secondDetail
                ON secondDetail.FSBCommissionID = secondFc.FSBCommissionID
               AND secondDetail.FSBTrackingID = re.FSBTrackingID
        ),

        RankedScreenRows AS
        (
            SELECT
                sr.*,
                ROW_NUMBER() OVER
                (
                    PARTITION BY
                        sr.PromotionID,
                        sr.SponsorID,
                        sr.SponsorFSB1Start,
                        CASE
                            WHEN sr.TrackingFSBType = 'FSB1_EXT' THEN 'FSB1'
                            ELSE sr.TrackingFSBType
                        END
                    ORDER BY
                        sr.OrderDate,
                        sr.OrderID,
                        sr.PromoterID,
                        sr.FSBTrackingID
                ) AS FSBDisplayRank
            FROM ScreenRows sr
        ),

        ProjectedScreenRows AS
        (
            SELECT
                rsr.*,

                rsr.FSB1StartDate AS ProjectedFSB1StartDate,

                COALESCE
                (
                    rsr.FSB1EndDate,
                    DATEADD(DAY, 7, rsr.SponsorFSB1Start)
                ) AS ProjectedFSB1EndDate,

                COALESCE
                (
                    rsr.FSB1EndDate,
                    DATEADD(DAY, 7, rsr.SponsorFSB1Start)
                ) AS ProjectedFSB1ExtStartDate,

                COALESCE
                (
                    rsr.FSB1ExtEndDate,
                    DATEADD(DAY, 14, rsr.SponsorFSB1Start)
                ) AS ProjectedFSB1ExtEndDate,

                COALESCE
                (
                    rsr.FSB2StartDate,
                    rsr.FSB1EndDate,
                    DATEADD(DAY, 7, rsr.SponsorFSB1Start)
                ) AS ProjectedFSB2StartDate,

                COALESCE
                (
                    rsr.FSB2EndDate,
                    DATEADD
                    (
                        DAY,
                        7,
                        COALESCE
                        (
                            rsr.FSB2StartDate,
                            rsr.FSB1EndDate,
                            DATEADD(DAY, 7, rsr.SponsorFSB1Start)
                        )
                    )
                ) AS ProjectedFSB2EndDate,

                COALESCE
                (
                    rsr.FSB3StartDate,
                    rsr.FSB2EndDate,
                    DATEADD(DAY, 14, rsr.SponsorFSB1Start)
                ) AS ProjectedFSB3StartDate,

                COALESCE
                (
                    rsr.FSB3EndDate,
                    DATEADD
                    (
                        DAY,
                        7,
                        COALESCE
                        (
                            rsr.FSB3StartDate,
                            rsr.FSB2EndDate,
                            DATEADD(DAY, 14, rsr.SponsorFSB1Start)
                        )
                    )
                ) AS ProjectedFSB3EndDate
            FROM RankedScreenRows rsr
        )

        SELECT
            PromotionID,
            SponsorID,
            SponsorFSB1Start,

            ProjectedFSB1StartDate AS FSB1StartDate,
            ProjectedFSB1EndDate AS FSB1EndDate,

            ProjectedFSB1ExtStartDate AS FSB1ExtStartDate,
            ProjectedFSB1ExtEndDate AS FSB1ExtEndDate,

            ProjectedFSB2StartDate AS FSB2StartDate,
            ProjectedFSB2EndDate AS FSB2EndDate,

            ProjectedFSB3StartDate AS FSB3StartDate,
            ProjectedFSB3EndDate AS FSB3EndDate,

            TrackingFSBType AS FSB,

            CommissionFSBType,
            TrackingFSBType,

            CASE
                WHEN TrackingFSBType = 'FSB1_EXT' THEN 1
                ELSE 0
            END AS IsFSB1Extension,

            FSBTrackingID,

            PromoterID,
            UserProfileID,
            UserName,

            COALESCE
            (
                NULLIF
                (
                    LTRIM
                    (
                        RTRIM
                        (
                            ISNULL(FirstName, '') + ' ' + ISNULL(LastName, '')
                        )
                    ),
                    ''
                ),
                UserName,
                CONVERT(VARCHAR(50), PromoterID)
            ) AS Ambassador,

            PromoterEnrollDate,

            OrderID,
            OrderDate,
            OrderStatus,

            ProductID,
            ISNULL(ProductName, CONVERT(VARCHAR(50), ProductID)) AS Product,

            FirstRPHID,
            FirstRPHCreateDate,
            FirstRPHDays,

            SecondRPHID,
            SecondRPHCreateDate,
            SecondRPHDays,

            LastSuccessfulRPHCreateDate,
            SuccessfulRecurringPaymentsHistoryCount,

            RecurringPaymentNextPaymentDate,
            RecurringPaymentCount,

            COALESCE(LastSuccessfulRPHCreateDate, PromoterEnrollDate) AS LastPaymentCreateDate,

            CASE
                WHEN LastSuccessfulRPHCreateDate IS NULL THEN RecurringPaymentNextPaymentDate
                ELSE COALESCE(DATEADD(MONTH, 1, PromoterEnrollDate), RecurringPaymentNextPaymentDate)
            END AS RenewalDate,

            ValidRenewalRPHID,
            ValidRenewalCreateDate,
            ValidRenewalSource,
            RenewalDaysFromOrderDate,

            CASE
                WHEN ValidRenewalRPHID IS NOT NULL THEN 1
                ELSE 0
            END AS HasValidRenewal,

            FirstFSBCommissionID,
            FirstCommissionCreatedAt,

            SecondFSBCommissionID,
            SecondCommissionCreatedAt,

            CASE
                WHEN SecondFSBCommissionDetailID IS NOT NULL THEN 1
                ELSE 0
            END AS SecondHalfPaid,

            CASE
                WHEN SecondFSBCommissionDetailID IS NOT NULL THEN ValidRenewalCreateDate
                ELSE NULL
            END AS SecondHalfGrantedCreateDate,

            CASE
                WHEN ISNULL(OrderStatus, '') <> 'Active'
                    THEN 'RED'

                WHEN ISNULL(SuccessfulRecurringPaymentsHistoryCount, 0) = 0
                 AND RecurringPaymentNextPaymentDate IS NOT NULL
                 AND CAST(RecurringPaymentNextPaymentDate AS DATE) >= CAST(GETDATE() AS DATE)
                    THEN 'YELLOW'

                WHEN ISNULL(SuccessfulRecurringPaymentsHistoryCount, 0) > 0
                 AND ValidRenewalRPHID IS NOT NULL
                    THEN 'GREEN'

                ELSE 'RED'
            END AS StatusColor,

            CASE
                WHEN ISNULL(OrderStatus, '') <> 'Active'
                    THEN 0

                WHEN ISNULL(SuccessfulRecurringPaymentsHistoryCount, 0) = 0
                 AND RecurringPaymentNextPaymentDate IS NOT NULL
                 AND CAST(RecurringPaymentNextPaymentDate AS DATE) >= CAST(GETDATE() AS DATE)
                    THEN 2

                WHEN ISNULL(SuccessfulRecurringPaymentsHistoryCount, 0) > 0
                 AND ValidRenewalRPHID IS NOT NULL
                    THEN 1

                ELSE 0
            END AS StatusCode,

            CASE
                WHEN ISNULL(OrderStatus, '') <> 'Active'
                    THEN 'MEMBERSHIP_CANCELLED'

                WHEN ISNULL(SuccessfulRecurringPaymentsHistoryCount, 0) = 0
                 AND RecurringPaymentNextPaymentDate IS NOT NULL
                 AND CAST(RecurringPaymentNextPaymentDate AS DATE) < CAST(GETDATE() AS DATE)
                    THEN 'RENEWAL_OVERDUE'

                WHEN ISNULL(SuccessfulRecurringPaymentsHistoryCount, 0) = 0
                 AND RecurringPaymentNextPaymentDate IS NOT NULL
                 AND CAST(RecurringPaymentNextPaymentDate AS DATE) >= CAST(GETDATE() AS DATE)
                    THEN 'ENROLLMENT_ONLY_PENDING_RENEWAL'

                WHEN ISNULL(SuccessfulRecurringPaymentsHistoryCount, 0) = 0
                    THEN 'RENEWAL_DATE_NOT_FOUND'

                WHEN ValidRenewalRPHID IS NULL
                    THEN 'RENEWAL_PAID_OUTSIDE_ALLOWED_DATES'

                WHEN SecondFSBCommissionDetailID IS NOT NULL
                    THEN 'SECOND_HALF_GRANTED'

                ELSE 'VALID_RENEWAL_PAID'
            END AS StatusText

        INTO #ScreenRows
        FROM ProjectedScreenRows
        WHERE FSBDisplayRank <= 2;

        -----------------------------------------------------------------------
        -- 4. OUTPUT
        --
        -- @ShowAllColumns = 1:
        --      full technical/debug/tracking result.
        --
        -- @ShowAllColumns IS NULL or 0:
        --      compact UI summary.
        -----------------------------------------------------------------------

        IF ISNULL(@ShowAllColumns, 0) = 1
        BEGIN
            SELECT
                PromotionID,
                SponsorID,
                SponsorFSB1Start,

                FSB1StartDate,
                FSB1EndDate,

                FSB1ExtStartDate,
                FSB1ExtEndDate,

                FSB2StartDate,
                FSB2EndDate,
                FSB3StartDate,
                FSB3EndDate,

                FSB,

                CommissionFSBType,
                TrackingFSBType,
                IsFSB1Extension,

                FSBTrackingID,

                PromoterID,
                UserProfileID,
                Ambassador,

                PromoterEnrollDate,

                OrderID,
                OrderDate,
                OrderStatus,

                ProductID,
                Product,

                FirstRPHID,
                FirstRPHCreateDate,
                FirstRPHDays,

                SecondRPHID,
                SecondRPHCreateDate,
                SecondRPHDays,

                LastSuccessfulRPHCreateDate,
                SuccessfulRecurringPaymentsHistoryCount,

                RecurringPaymentNextPaymentDate,
                RecurringPaymentCount,

                LastPaymentCreateDate,
                RenewalDate,

                ValidRenewalRPHID,
                ValidRenewalCreateDate,
                ValidRenewalSource,
                RenewalDaysFromOrderDate,
                HasValidRenewal,

                FirstFSBCommissionID,
                FirstCommissionCreatedAt,

                SecondFSBCommissionID,
                SecondCommissionCreatedAt,
                SecondHalfPaid,
                SecondHalfGrantedCreateDate,

                StatusColor,
                StatusCode,
                StatusText,
                UserName
            FROM #ScreenRows
            ORDER BY
                SponsorID,
                SponsorFSB1Start,
                CASE
                    WHEN TrackingFSBType = 'FSB1' THEN 1
                    WHEN TrackingFSBType = 'FSB1_EXT' THEN 2
                    WHEN TrackingFSBType = 'FSB2' THEN 3
                    WHEN TrackingFSBType = 'FSB3' THEN 4
                    ELSE 99
                END,
                OrderDate,
                OrderID,
                PromoterID;
        END
        ELSE
        BEGIN
            SELECT
                SponsorID,
                SponsorFSB1Start,

                FSB1StartDate,
                FSB1EndDate,

                FSB1ExtStartDate,
                FSB1ExtEndDate,

                FSB2StartDate,
                FSB2EndDate,
                FSB3StartDate,
                FSB3EndDate,

                FSB,

                Ambassador,

                PromoterEnrollDate AS EnrollDate,

                Product,

                LastPaymentCreateDate AS LastPayment,
                RenewalDate,
                RecurringPaymentCount,

                StatusColor,
                StatusCode,
                StatusText,

                OrderID,

                TrackingFSBType,
                CommissionFSBType,

                HasValidRenewal,
                ValidRenewalRPHID,

                SecondHalfPaid,
                UserName

            FROM #ScreenRows
            ORDER BY
                SponsorID,
                SponsorFSB1Start,
                CASE
                    WHEN TrackingFSBType = 'FSB1' THEN 1
                    WHEN TrackingFSBType = 'FSB1_EXT' THEN 2
                    WHEN TrackingFSBType = 'FSB2' THEN 3
                    WHEN TrackingFSBType = 'FSB3' THEN 4
                    ELSE 99
                END,
                OrderDate,
                OrderID,
                PromoterID;
        END;

    END TRY
    BEGIN CATCH

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
