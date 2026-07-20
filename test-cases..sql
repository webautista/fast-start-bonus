        -----------------------------------------------------------------------
        -- COMMISSION REPORT
        -----------------------------------------------------------------------

        ;WITH ReportBase AS
        (
            SELECT
                fc.FSBCommissionID,
                fc.PromotionID,
                fc.SponsorID,
                fc.SponsorFSB1Start,
                fc.FSBType AS CommissionFSBType,
                fc.HalfType,

                ft.FSBTrackingID,
                ft.PromoterID,
                ft.OrderID,
                o.OrderDate,

                ft.FSBType AS TrackingFSBType,

                ft.FirstRPHID,
                rphFirst.CreateDate AS FirstRPHCreateDate,
                DATEDIFF(DAY, o.OrderDate, rphFirst.CreateDate) AS FirstRPHDays,

                ft.SecondRPHID,
                rphSecond.CreateDate AS SecondRPHCreateDate,
                DATEDIFF(DAY, o.OrderDate, rphSecond.CreateDate) AS SecondRPHDays,

                ft.SponsorFSB1End,
                ft.SponsorFSB1ExtEnd,
                ft.SponsorFSB2Start,
                ft.SponsorFSB2End,
                ft.SponsorFSB3Start,
                ft.SponsorFSB3End

            FROM dbo.FSBCommission fc
            INNER JOIN dbo.FSBCommissionDetail fcd
                ON fcd.FSBCommissionID = fc.FSBCommissionID
            INNER JOIN dbo.FSBTrackings ft
                ON ft.FSBTrackingID = fcd.FSBTrackingID
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
        ),

        RenewalEval AS
        (
            SELECT
                rb.*,

                CASE
                    WHEN rb.FirstRPHID IS NOT NULL
                     AND DATEDIFF(DAY, rb.OrderDate, rb.FirstRPHCreateDate) BETWEEN 1 AND 44
                        THEN rb.FirstRPHID

                    WHEN rb.SecondRPHID IS NOT NULL
                     AND DATEDIFF(DAY, rb.OrderDate, rb.SecondRPHCreateDate) BETWEEN 1 AND 44
                        THEN rb.SecondRPHID

                    ELSE NULL
                END AS ValidRenewalRPHID,

                CASE
                    WHEN rb.FirstRPHID IS NOT NULL
                     AND DATEDIFF(DAY, rb.OrderDate, rb.FirstRPHCreateDate) BETWEEN 1 AND 44
                        THEN rb.FirstRPHCreateDate

                    WHEN rb.SecondRPHID IS NOT NULL
                     AND DATEDIFF(DAY, rb.OrderDate, rb.SecondRPHCreateDate) BETWEEN 1 AND 44
                        THEN rb.SecondRPHCreateDate

                    ELSE NULL
                END AS ValidRenewalCreateDate,

                CASE
                    WHEN rb.FirstRPHID IS NOT NULL
                     AND DATEDIFF(DAY, rb.OrderDate, rb.FirstRPHCreateDate) BETWEEN 1 AND 44
                        THEN 'FirstRPHID'

                    WHEN rb.SecondRPHID IS NOT NULL
                     AND DATEDIFF(DAY, rb.OrderDate, rb.SecondRPHCreateDate) BETWEEN 1 AND 44
                        THEN 'SecondRPHID'

                    ELSE NULL
                END AS ValidRenewalSource,

                CASE
                    WHEN rb.FirstRPHID IS NOT NULL
                     AND DATEDIFF(DAY, rb.OrderDate, rb.FirstRPHCreateDate) BETWEEN 1 AND 44
                        THEN DATEDIFF(DAY, rb.OrderDate, rb.FirstRPHCreateDate)

                    WHEN rb.SecondRPHID IS NOT NULL
                     AND DATEDIFF(DAY, rb.OrderDate, rb.SecondRPHCreateDate) BETWEEN 1 AND 44
                        THEN DATEDIFF(DAY, rb.OrderDate, rb.SecondRPHCreateDate)

                    ELSE NULL
                END AS RenewalDaysFromOrderDate
            FROM ReportBase rb
        )

        SELECT
            u.UserName, 
            FSBCommissionID,
            PromotionID,
            re.SponsorID,
            SponsorFSB1Start,

            CommissionFSBType,
            HalfType,

            FSBTrackingID,
            re.PromoterID,
            OrderID,
            OrderDate,

            TrackingFSBType,

            SponsorFSB1End,
            SponsorFSB1ExtEnd,
            SponsorFSB2Start,
            SponsorFSB2End,
            SponsorFSB3Start,
            SponsorFSB3End,

            FirstRPHID,
            FirstRPHCreateDate,
            FirstRPHDays,

            SecondRPHID,
            SecondRPHCreateDate,
            SecondRPHDays,

            ValidRenewalRPHID,
            ValidRenewalCreateDate,
            ValidRenewalSource,
            RenewalDaysFromOrderDate,

            CASE
                WHEN ValidRenewalRPHID IS NOT NULL THEN 1
                ELSE 0
            END AS HasValidRenewal,

            CASE
                WHEN HalfType = 'SECOND' THEN ValidRenewalCreateDate
                ELSE NULL
            END AS SecondHalfGrantedCreateDate,

            CASE
                WHEN HalfType = 'FIRST' THEN 'USED_FOR_FIRST_HALF'
                WHEN HalfType = 'SECOND' AND ValidRenewalRPHID IS NOT NULL THEN 'USED_FOR_SECOND_HALF'
                WHEN HalfType = 'SECOND' AND ValidRenewalRPHID IS NULL THEN 'SECOND_HALF_DETAIL_WITHOUT_VALID_RENEWAL'
                ELSE 'UNKNOWN'
            END AS AuditStatus

        FROM RenewalEval re
        inner join Promoters sponsor on sponsor.promoterid = re.SponsorID
        inner join UserProfile u on u.UserId = sponsor.UserProfileId
       where HalfType = 'FIRST' and TrackingFSBType = 'FSB1' AND ValidRenewalRPHID IS NOT NULL
        ORDER BY
            re.SponsorID,
            SponsorFSB1Start,
            CommissionFSBType,
            HalfType,
            TrackingFSBType,
            OrderDate,
            OrderID;
/*
    FSB2
    TLTravels
    dylanbuchoux
    FSB1
    leehosung
    angeliquedenin
    FSB3
    AnnaZakkar
    Pavlushko2121

    FSB3
    rroncea
    RKatharina
    FSB2
    KJA10004
    TetianaZhulkivska
    FSB1
    martincaron1
    hiro33
*/