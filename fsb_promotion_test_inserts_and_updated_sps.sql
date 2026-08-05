
/*
================================================================================
FSB TEST DATA + UPDATED STORED PROCEDURES
PromotionProducts mode: EXCLUSION-BASED
Old FSB rule: AND o.ProductID NOT IN (4, 22)
New rule: dbo.PromotionProducts stores excluded products using IsExcluded = 1
================================================================================
*/


-------------------------------------------------------------------------------
-- 2. INSERT PRODUCTION-LIKE PROMOTION
-------------------------------------------------------------------------------

IF NOT EXISTS
(
    SELECT 1
    FROM dbo.Promotions
    WHERE Code = 'FSB_2026_MAIN'
)
BEGIN
    INSERT INTO dbo.Promotions
    (
        Code,
        Type,
        PromoName,
        PromoDesc,
        StartDate,
        EndDate
    )
    VALUES
    (
        'FSB_2026_MAIN',
        'FSB',
        'Fast Start Bonus 2026',
        'Main Fast Start Bonus promotion for 2026 rollout.',
        '2026-01-01 00:00:00',
        '2026-12-31 23:59:59'
    );
END;
GO

-------------------------------------------------------------------------------
-- 4. INSERT EXCLUDED PRODUCTS FOR MAIN PROMOTION
-- Old logic: AND o.ProductID NOT IN (4, 22)
-------------------------------------------------------------------------------

DECLARE @PromotionID BIGINT;

SELECT @PromotionID = PromotionID
FROM dbo.Promotions
WHERE Code = 'FSB_2026_MAIN';

IF @PromotionID IS NULL
BEGIN
    RAISERROR('Promotion FSB_2026_MAIN was not found.', 16, 1);
    RETURN;
END;

IF NOT EXISTS
(
    SELECT 1
    FROM dbo.PromotionProducts
    WHERE PromotionID = @PromotionID
      AND ProductID = 4
)
BEGIN
    INSERT INTO dbo.PromotionProducts
    (
        PromotionID,
        ProductID,
        IsExcluded
    )
    VALUES
    (
        @PromotionID,
        4,
        1
    );
END;
IF NOT EXISTS
(
    SELECT 1
    FROM dbo.PromotionProducts
    WHERE PromotionID = @PromotionID
      AND ProductID = 18
)
BEGIN
    INSERT INTO dbo.PromotionProducts
    (
        PromotionID,
        ProductID,
        IsExcluded
    )
    VALUES
    (
        @PromotionID,
        19,
        1
    );
END;
IF NOT EXISTS
(
    SELECT 1
    FROM dbo.PromotionProducts
    WHERE PromotionID = @PromotionID
      AND ProductID = 22
)
BEGIN
    INSERT INTO dbo.PromotionProducts
    (
        PromotionID,
        ProductID,
        IsExcluded
    )
    VALUES
    (
        @PromotionID,
        22,
        1
    );
END;
GO


-------------------------------------------------------------------------------
-- 5. VALIDATE PROMOTION CONFIGURATION
-------------------------------------------------------------------------------

SELECT
    p.PromotionID,
    p.Code,
    p.Type,
    p.PromoName,
    p.StartDate,
    p.EndDate,
    pp.ProductID,
    pp.IsExcluded
FROM dbo.Promotions p
LEFT JOIN dbo.PromotionProducts pp
    ON pp.PromotionID = p.PromotionID
WHERE p.Code IN ('FSB_2026_MAIN')
ORDER BY
    p.Code,
    pp.ProductID;
GO

select * from PromotionProducts
/*
-------------------------------------------------------------------------------
-- 6. RUN TEST
-------------------------------------------------------------------------------

DECLARE @PromotionID BIGINT;
SELECT @PromotionID = PromotionID
FROM dbo.Promotions
WHERE Code = 'FSB_2026_MAIN';

EXEC dbo.FSBTrackings_Load @PromotionID = @PromotionID;
EXEC dbo.FSBCommission_Generate @PromotionID = @PromotionID;
EXEC dbo.FSBCommission_Report @SponsorID = 323861;
EXEC dbo.FSBCommission_TrackingReport @SponsorID = 323861;
GO
*/

/*TrackingFastStartBonus/TLTravels


Username ishiharu
Username yellowhead
Username ksj0301
Username natasatravel
Username 3goodtime
*/


select u.Email, u.UserName, p.* from promoters p inner join dbo.UserProfile u on p.UserProfileId = u.UserId
where username in (
--'trixiecreates','nickbramble','TLTravels')
'3goodtime','natasatravel','ksj0301','yellowhead','ishiharu') 
or userid = 660959

--select u.UserProfileid = 648007
select * from dbo.Product where ProductID in (4,19,22)
--648007
select * from promoters u where u.UserProfileid = 660959
--	Andrey Rakhmanin

truncate table dbo.FSBCandidates;
truncate table dbo.FSBTrackings;
truncate table dbo.FSBCommission;
truncate table dbo.FSBCommissionDetail;

-- order by SponsorFSB1Start asc

select * from dbo.UserProfile where UserID in (638695, 640199, 639097)

select 
--u.Email, u.UserName, u.SponsorID as UserProfileSponsorID, s.UserProfileId, c.SponsorMemberID, p.promoterid, 
o.OrderID, o.OrderDate, u.Email, u.UserName, u.SponsorID, c.UserID, c.SponsorMemberID
-- p.EnrollDate, p.SponsorID,  
--us.Email SponsorEmail, us.UserName SponsorUserName, s.FSB1StartDate as SponsorFSB1StartDate, DATEADD(DAY, 21, s.FSB1StartDate) SponsorFSB3EndDate 

from dbo.[Order] o 
inner join dbo.MWRCustomers c on o.CustomerId = c.CustomerID and o.[Status] = 'Active' and o.ProductID not in (4,19,22)
inner join dbo.UserProfile u on c.UserID = u.UserId and u.ApplicationName = 'mwrlife.com'
where c.SponsorMemberID = 638695
--UserID in (638695, 640199, 639097)



select u.Email, u.UserName, u.SponsorID as UserProfileSponsorID, s.UserProfileId, c.SponsorMemberID, p.promoterid, o.OrderID, o.OrderDate, p.EnrollDate, p.SponsorID,  us.Email SponsorEmail, us.UserName SponsorUserName, s.FSB1StartDate as SponsorFSB1StartDate, DATEADD(DAY, 21, s.FSB1StartDate) SponsorFSB3EndDate 
from promoters p 
inner join promoters s on p.SponsorId = s.PromoterId
inner join dbo.UserProfile us on s.UserProfileId = us.UserId and us.username = 'AGTravelandMore' -- in ('Johyoyoun7')
--,'ksj0301','3goodtime','natasatravel','ksj0301','yellowhead','ishiharu') 
inner join dbo.UserProfile u on p.UserProfileId = u.UserId --and u.ApplicationName = 'mwrlife.com'
inner join dbo.MWRCustomers c on c.UserID = u.UserId
inner join dbo.[Order] o on o.CustomerId = c.CustomerID and o.[Status] = 'Active' and o.ProductID not in (4,19,22)
order by SponsorID asc

select * from dbo.UserProfile us where us.username in ('ohyoyoun7')

select * from dbo.FSBTrackings where candidateType = 'Customer'
select * from dbo.FSBTrackings  where SponsorID in (325853,325948,326814,326851,326929, 316183) order by SponsorID asc;
select o.* from dbo.[Order] o inner join dbo.FSBTrackings t on o.OrderId = t.OrderID where SponsorID = 327259;
select rph.* from dbo.RecurringPaymentsHistory rph inner join dbo.FSBTrackings t on rph.OrderId = t.OrderID where SponsorID = 327259;
select * from dbo.FSBCommission where SponsorID = 327259;
select cd.* from dbo.FSBCommissionDetail cd inner join dbo.FSBTrackings t on cd.FSBTrackingID = t.FSBTrackingID and t.SponsorID = 327259;

select * from dbo.FSBTrackings ft
left JOIN dbo.FSBCommissionDetail fcd ON ft.FSBTrackingID = fcd.FSBTrackingID  
left JOIN dbo.FSBCommission fc on fcd.FSBCommissionID = fc.FSBCommissionID
where ft.SponsorID = 319936


EXEC dbo.FSBCommission_TrackingReport @SponsorID = 316183;
EXEC dbo.FSBCommission_TrackingReport @SponsorID = 327259, @ShowAllColumns = 1;

EXEC dbo.FSBCommission_Report @SponsorID = 344015;
select * from promoters u where u.UserProfileid = 632961
EXEC dbo.FSBCommission_TrackingReport @SponsorID = 312870, @ShowAllColumns = 1;
EXEC dbo.FSBCommission_TrackingReport @SponsorID = 344015, @ShowAllColumns = 1;

select * from userprofile where userid in (637069,637071);
select top 1 prod.*, o.* from dbo.[order] o inner JOIN dbo.Product prod ON prod.ProductID = o.ProductID
where [Name] = 'Travel Advantage Pro' and o.IsEliteTravelAdvantagePro = 1
