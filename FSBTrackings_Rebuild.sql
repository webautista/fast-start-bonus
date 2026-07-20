CREATE OR ALTER PROCEDURE dbo.FSBTrackings_Rebuild
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    BEGIN TRY
        BEGIN TRAN;

        DELETE FROM dbo.FSBTrackings;

        ;WITH Base AS
        (
            SELECT DISTINCT
                sponsor.PromoterID AS SponsorID,
                child.PromoterID   AS PromoterID,
                o.OrderID,
                o.OrderDate,
                sponsor.FSB1StartDate,
                sponsor.FSB1EndDate,
                DATEADD(DAY, 14, sponsor.FSB1StartDate) AS FSB1ExtendedEndDate,
                sponsor.FSB2StartDate,
                sponsor.FSB2EndDate,
                sponsor.FSB3StartDate,
                sponsor.FSB3EndDate
            FROM dbo.Promoters child
            INNER JOIN dbo.Promoters sponsor
                ON sponsor.PromoterID = child.SponsorID
            INNER JOIN dbo.UserProfile upChild
                ON upChild.UserID = child.UserProfileID
            INNER JOIN dbo.MWRCustomers c
                ON c.UserID = upChild.UserID
            INNER JOIN dbo.[Order] o
                ON o.CustomerID = c.CustomerID
            WHERE o.Status = 'Active'
              AND o.ProductID NOT IN (4, 22)
              AND o.OrderDate IS NOT NULL
              AND sponsor.FSB1StartDate IS NOT NULL
              AND sponsor.FSB1EndDate IS NOT NULL
        ),
        Classified AS
        (
            SELECT
                b.SponsorID,
                b.FSB1StartDate,
                b.FSB1EndDate,
                b.FSB1ExtendedEndDate,
                b.FSB2StartDate,
                b.FSB2EndDate,
                b.FSB3StartDate,
                b.FSB3EndDate,
                b.PromoterID,
                b.OrderID,
                b.OrderDate,
                CASE
                    WHEN b.OrderDate >= b.FSB1StartDate
                     AND b.OrderDate < DATEADD(DAY, 1, b.FSB1EndDate)
                        THEN 'FSB1'

                    WHEN b.OrderDate > b.FSB1EndDate
                     AND b.OrderDate < DATEADD(DAY, 1, b.FSB1ExtendedEndDate)
                        THEN 'FSB1_EXT'

                    WHEN b.FSB2StartDate IS NOT NULL
                     AND b.FSB2EndDate IS NOT NULL
                     AND b.OrderDate >= b.FSB2StartDate
                     AND b.OrderDate < DATEADD(DAY, 1, b.FSB2EndDate)
                        THEN 'FSB2'

                    WHEN b.FSB3StartDate IS NOT NULL
                     AND b.FSB3EndDate IS NOT NULL
                     AND b.OrderDate >= b.FSB3StartDate
                     AND b.OrderDate < DATEADD(DAY, 1, b.FSB3EndDate)
                        THEN 'FSB3'

                    ELSE NULL
                END AS FSBType
            FROM Base b
        ),
        Payments AS
        (
            SELECT
                c.SponsorID,
                c.FSB1StartDate,
                c.FSB1EndDate,
                c.FSB1ExtendedEndDate,
                c.FSB2StartDate,
                c.FSB2EndDate,
                c.FSB3StartDate,
                c.FSB3EndDate,
                c.PromoterID,
                c.OrderID,
                c.FSBType,
                fp.FirstRPHID,
                sp.SecondRPHID
            FROM Classified c
            OUTER APPLY
            (
                SELECT TOP (1)
                    rph.ID AS FirstRPHID
                FROM dbo.RecurringPaymentsHistory rph
                WHERE rph.OrderID = c.OrderID
                  AND rph.Status = 'SUCCESS'
                ORDER BY rph.CreateDate ASC, rph.ID ASC
            ) fp
            OUTER APPLY
            (
                SELECT TOP (1)
                    rph.ID AS SecondRPHID
                FROM dbo.RecurringPaymentsHistory rph
                WHERE rph.OrderID = c.OrderID
                  AND rph.Status = 'SUCCESS'
                  AND DATEDIFF(DAY, c.OrderDate, rph.CreateDate) BETWEEN 30 AND 44
                ORDER BY rph.CreateDate ASC, rph.ID ASC
            ) sp
            WHERE c.FSBType IS NOT NULL
        )
        INSERT INTO dbo.FSBTrackings
        (
            SponsorID,
            SponsorFSB1Start, SponsorFSB1End, SponsorFSB1ExtEnd, SponsorFSB2Start, SponsorFSB2End, SponsorFSB3Start, SponsorFSB3End,
            PromoterID, OrderID, FSBType, FirstRPHID, SecondRPHID
        )
        SELECT
            p.SponsorID,
            p.FSB1StartDate, p.FSB1EndDate, p.FSB1ExtendedEndDate, p.FSB2StartDate, p.FSB2EndDate, p.FSB3StartDate, p.FSB3EndDate,
            p.PromoterID, p.OrderID, p.FSBType, p.FirstRPHID, p.SecondRPHID
        FROM Payments p;

        COMMIT TRAN;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0
            ROLLBACK TRAN;

        THROW;
    END CATCH
END;
GO