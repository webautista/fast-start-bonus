USE [mwrlifelive]
GO
/****** Object:  StoredProcedure [dbo].[FSBCommission_TrackingReport]    Script Date: 7/7/2026 8:43:00 PM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
--USE [mwrlifelive]
--GO
--/****** Object:  StoredProcedure [dbo].[FSBCommission_TrackingReport]    Script Date: 30-06-2026 11:48:03 ******/
--SET ANSI_NULLS ON
--GO
--SET QUOTED_IDENTIFIER ON
--GO
--FSBCommission_TrackingReport 332994,0 313790,0


 ALTER PROCEDURE [dbo].[FSBCommission_TrackingReport] (     
 --declare 
 @SponsorID BIGINT =NULL, --= 332994,
    @ShowAllColumns BIT = NULL--,1
	) 
 AS BEGIN    
 
 
 
 SET NOCOUNT ON;      
 DECLARE @EffectivePromotionID BIGINT;      
 BEGIN TRY          
 -----------------------------------------------------------------------         
 -- 1. RESOLVE CURRENT ACTIVE FSB PROMOTION         
 -----------------------------------------------------------------------          
 SELECT TOP (1)             @EffectivePromotionID = p.PromotionID
FROM dbo.Promotions p
WHERE p.Type = 'FSB'           AND GETDATE() >= p.StartDate           AND GETDATE() <= p.EndDate
ORDER BY p.StartDate DESC,
    p.PromotionID DESC;          
 
 IF @EffectivePromotionID IS NULL OR @EffectivePromotionID = 0         
 BEGIN             
 RAISERROR('No active FSB promotion was found.',
    16,
    1);             
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
 --3. BUILD TRACKING SCREEN ROWS         --         
 -- Base = FIRST commission rows only.         
 -- SECOND information is joined into the FIRST row.         
 -- This avoids duplicate FIRST / SECOND rows in the UI.         
 -----------------------------------------------------------------------          
IF OBJECT_ID('tempdb..#ScreenRows') IS NOT NULL             
DROP TABLE #ScreenRows; 

IF OBJECT_ID('tempdb..#tmpFSBResultScreenRowsFull') IS NOT NULL             
DROP TABLE #tmpFSBResultScreenRowsFull;

IF OBJECT_ID('tempdb..#tmpFSBResultScreenRows') IS NOT NULL             
DROP TABLE #tmpFSBResultScreenRows;




;WITH FirstRows AS         
(             SELECT                 firstFc.FSBCommissionID AS FirstFSBCommissionID,
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
    DATEDIFF(DAY,
    o.OrderDate,
    rphFirst.CreateDate) AS FirstRPHDays,
    ft.SecondRPHID,
    rphSecond.CreateDate AS SecondRPHCreateDate,
    DATEDIFF(DAY,
    o.OrderDate,
    rphSecond.CreateDate) AS SecondRPHDays,
    lastSuccessfulRph.LastSuccessfulRPHCreateDate,
    ISNULL(lastSuccessfulRph.SuccessfulRPHCount,
    0) AS SuccessfulRecurringPaymentsHistoryCount,
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
	ISNULL(o.IsEliteTravelAdvantagePro, 0) AS IsElite,
    ISNULL(o.OrderLevel, 0) AS OrderLevel,
    o.Turbo,
    --prod.[Name] AS ProductName,
	 CASE
        WHEN o.ProductID = 20 AND ISNULL(o.IsEliteTravelAdvantagePro,0)=0 THEN 'Travel Advantage™ Pro'
        WHEN (o.ProductID = 20 AND ISNULL(o.IsEliteTravelAdvantagePro,0)=1) OR o.ProductID = 23 THEN 'Travel Advantage™ Elite'
        WHEN o.ProductID = 27 THEN 'Travel Advantage™ Elite180'
        WHEN o.ProductID = 26  THEN 'Travel Advantage™ Pro180'
        WHEN o.ProductID = 25 THEN 'Travel Advantage™ Plus180'
        WHEN o.ProductID = 28 THEN 'Travel Advantage™ Plus'
        WHEN o.ProductID = 19 AND ISNULL(o.OrderLevel,0)=2 THEN 'Travel Advantage™ VIP 365'
        WHEN o.ProductID = 19 AND ISNULL(o.OrderLevel,0)=1 THEN 'Travel Advantage™ VIP 180'
        WHEN o.ProductID = 19 THEN 'Travel Advantage™ VIP'
        WHEN o.ProductID = 22 THEN 'Travel Advantage™ Guest'
        WHEN o.ProductID = 4 THEN 'App Subscription'
        WHEN o.ProductID = 3 THEN 'Life Essentials'
        WHEN o.ProductID = 21 THEN 'Lifestyle Bundle'
        WHEN o.ProductID = 24 THEN 'Lifestyle Mall Access'
        WHEN o.ProductID = 18 THEN 'Financial Edge'
        ELSE ISNULL(prod.[Name],'')
    END
    +
    CASE
        WHEN ISNULL(o.Turbo,0)=1 THEN ' TURBO'
        ELSE ''
    END AS ProductName
FROM dbo.FSBCommission firstFc              
INNER JOIN dbo.FSBCommissionDetail firstDetail                 ON firstDetail.FSBCommissionID = firstFc.FSBCommissionID              
INNER JOIN dbo.FSBTrackings ft                 ON ft.FSBTrackingID = firstDetail.FSBTrackingID              
INNER JOIN dbo.[Order] o                 ON o.OrderID = ft.OrderID              
INNER JOIN dbo.Promoters promoter                 ON promoter.PromoterID = ft.PromoterID              
LEFT JOIN dbo.UserProfile up                 ON up.UserID = promoter.UserProfileID              
LEFT JOIN dbo.Product prod                 ON prod.ProductID = o.ProductID              
LEFT JOIN dbo.RecurringPaymentsHistory rphFirst
                 ON rphFirst.ID = ft.FirstRPHID                AND rphFirst.Status = 'SUCCESS'                AND ISNULL(rphFirst.Reverted,
    0) = 0              LEFT JOIN dbo.RecurringPaymentsHistory rphSecond                 
				 ON rphSecond.ID = ft.SecondRPHID                AND rphSecond.Status = 'SUCCESS'                AND ISNULL(rphSecond.Reverted,
    0) = 0              
	OUTER APPLY             (                 SELECT                     MAX(rph.CreateDate) AS LastSuccessfulRPHCreateDate,
    COUNT(1) AS SuccessfulRPHCount
FROM dbo.RecurringPaymentsHistory rph
WHERE rph.OrderId = ft.OrderID                   AND rph.[Status] = 'SUCCESS'                   
   AND ISNULL(rph.Reverted,
    0) = 0             ) lastSuccessfulRph              
   LEFT JOIN dbo.RecurringPayments rp                 ON rp.[OrderId] = ft.OrderID
WHERE firstFc.PromotionID = @EffectivePromotionID               AND firstFc.HalfType = 'FIRST'               
   AND (@SponsorID IS NULL OR firstFc.SponsorID = @SponsorID)         ),
    RenewalEval AS         (             SELECT                 fr.*,
    CASE                     WHEN fr.FirstRPHID IS NOT NULL                      
   AND DATEDIFF(DAY,
    fr.OrderDate,
    fr.FirstRPHCreateDate) BETWEEN 1 AND 44                         THEN fr.FirstRPHID                      WHEN fr.SecondRPHID IS NOT NULL                      AND DATEDIFF(DAY,
    fr.OrderDate,
    fr.SecondRPHCreateDate) BETWEEN 1 AND 44                         
   THEN fr.SecondRPHID                      ELSE NULL                 END AS ValidRenewalRPHID,
    CASE                     WHEN fr.FirstRPHID IS NOT NULL                      AND DATEDIFF(DAY,
    fr.OrderDate,
    fr.FirstRPHCreateDate) BETWEEN 1 AND 44             
            THEN fr.FirstRPHCreateDate                      WHEN fr.SecondRPHID IS NOT NULL                      AND DATEDIFF(DAY,
    fr.OrderDate,
    fr.SecondRPHCreateDate) BETWEEN 1 AND 44                         THEN fr.SecondRPHCreateDate                  
    ELSE NULL                 END AS ValidRenewalCreateDate,
    CASE                     WHEN fr.FirstRPHID IS NOT NULL                      AND DATEDIFF(DAY,
    fr.OrderDate,
    fr.FirstRPHCreateDate) BETWEEN 1 AND 44                         THEN
 'FirstRPHID'                      WHEN fr.SecondRPHID IS NOT NULL                      AND DATEDIFF(DAY,
    fr.OrderDate,
    fr.SecondRPHCreateDate) BETWEEN 1 AND 44                         THEN 'SecondRPHID'                      ELSE NULL                 END 
AS ValidRenewalSource,
    CASE                     WHEN fr.FirstRPHID IS NOT NULL                      AND DATEDIFF(DAY,
    fr.OrderDate,
    fr.FirstRPHCreateDate) BETWEEN 1 AND 44                         
THEN DATEDIFF(DAY,
    fr.OrderDate,
    fr.FirstRPHCreateDate)                      WHEN fr.SecondRPHID IS NOT NULL                      AND DATEDIFF(DAY,
    fr.OrderDate,
    fr.SecondRPHCreateDate) BETWEEN 1 AND 44                         THEN DATEDIFF(DAY,
    fr.OrderDate,
    fr.SecondRPHCreateDate)              
        ELSE NULL                 END AS RenewalDaysFromOrderDate
FROM FirstRows fr         ),
    ScreenRows AS         (             SELECT                 re.*,
    secondFc.FSBCommissionID AS SecondFSBCommissionID,
    secondFc.CreatedAt AS SecondCommissionCreatedAt,
    secondDetail.FSBCommissionDetailID AS SecondFSBCommissionDetailID
FROM RenewalEval re              LEFT JOIN dbo.FSBCommission secondFc                
		  ON secondFc.PromotionID = re.PromotionID                AND secondFc.SponsorID = re.SponsorID                AND secondFc.SponsorFSB1Start = re.SponsorFSB1Start                AND secondFc.FSBType = re.CommissionFSBType                AND secondFc.HalfType = 'SECOND'  
            LEFT JOIN dbo.FSBCommissionDetail secondDetail                 ON secondDetail.FSBCommissionID = secondFc.FSBCommissionID                AND secondDetail.FSBTrackingID = re.FSBTrackingID         )          SELECT             PromotionID,
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
    TrackingFSBType AS FSB,
    CommissionFSBType,
    TrackingFSBType,
    CASE                 WHEN TrackingFSBType = 'FSB1_EXT' THEN 1                 ELSE 0             END AS IsFSB1Extension,
    FSBTrackingID,
    PromoterID,
    UserProfileID,
    COALESCE             (                 NULLIF                 (                     LTRIM                     (                         RTRIM                         (       
                      ISNULL(FirstName,
    '') + ' ' + ISNULL(LastName,
    '')                         )                     ),
    ''                 ),
    UserName,
    CONVERT(VARCHAR(50),
    PromoterID)             ) AS
 Ambassador,
    PromoterEnrollDate,
    OrderID,
    OrderDate,
    OrderStatus,
    ProductID,
    ISNULL(ProductName,
    CONVERT(VARCHAR(50),
    ProductID)) AS Product,
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
    COALESCE(LastSuccessfulRPHCreateDate,
    PromoterEnrollDate) AS LastPaymentCreateDate,
    CASE                 WHEN LastSuccessfulRPHCreateDate IS NULL 
THEN RecurringPaymentNextPaymentDate                 ELSE COALESCE(DATEADD(MONTH,
    1,
    PromoterEnrollDate),
    RecurringPaymentNextPaymentDate)             END AS RenewalDate,
    ValidRenewalRPHID,
    ValidRenewalCreateDate,
    ValidRenewalSource,
    RenewalDaysFromOrderDate,
    CASE                 WHEN ValidRenewalRPHID IS NOT NULL THEN 1                 ELSE 0             END AS HasValidRenewal,
    FirstFSBCommissionID,
    FirstCommissionCreatedAt,
    SecondFSBCommissionID,
    SecondCommissionCreatedAt,
    CASE                 WHEN SecondFSBCommissionDetailID IS NOT NULL THEN 1                 ELSE 0             END AS SecondHalfPaid,
    CASE                 
WHEN SecondFSBCommissionDetailID IS NOT NULL THEN ValidRenewalCreateDate                 ELSE NULL             END AS SecondHalfGrantedCreateDate,
    CASE                 WHEN ISNULL(OrderStatus,
    '') <> 'Active'                     THEN 'RED'                  WHEN ISNULL
(SuccessfulRecurringPaymentsHistoryCount,
    0) = 0                  AND RecurringPaymentNextPaymentDate IS NOT NULL                  AND CAST(RecurringPaymentNextPaymentDate AS DATE) >= CAST(GETDATE() AS DATE)                     THEN 'YELLOW'              
    WHEN ISNULL(SuccessfulRecurringPaymentsHistoryCount,
    0) > 0                  AND ValidRenewalRPHID IS NOT NULL                     THEN 'GREEN'                  ELSE 'RED'             END AS StatusColor,
    CASE                 
	WHEN ISNULL(OrderStatus,
    '') <> 'Active'                     THEN 0                  WHEN ISNULL(SuccessfulRecurringPaymentsHistoryCount,
    0) = 0                  AND RecurringPaymentNextPaymentDate IS NOT NULL                  AND CAST(RecurringPaymentNextPaymentDate 
AS DATE) >= CAST(GETDATE() AS DATE)                     THEN 2                  WHEN ISNULL(SuccessfulRecurringPaymentsHistoryCount,
    0) > 0                  AND ValidRenewalRPHID IS NOT NULL                     THEN 1                  ELSE 0             
END AS StatusCode,
    CASE                 WHEN ISNULL(OrderStatus,
    '') <> 'Active'                     THEN 'MEMBERSHIP_CANCELLED'                  WHEN ISNULL(SuccessfulRecurringPaymentsHistoryCount,
    0) = 0                  
AND RecurringPaymentNextPaymentDate IS NOT NULL                  AND CAST(RecurringPaymentNextPaymentDate AS DATE) < CAST(GETDATE() AS DATE)                     THEN 'RENEWAL_OVERDUE'                  WHEN ISNULL(SuccessfulRecurringPaymentsHistoryCount,
    0) = 0               
   AND RecurringPaymentNextPaymentDate IS NOT NULL                  AND CAST(RecurringPaymentNextPaymentDate AS DATE) >= CAST(GETDATE() AS DATE)                     THEN 'ENROLLMENT_ONLY_PENDING_RENEWAL'                  
   WHEN ISNULL(SuccessfulRecurringPaymentsHistoryCount,
    0) = 0                     THEN 'RENEWAL_DATE_NOT_FOUND'                  WHEN ValidRenewalRPHID IS NULL                     THEN 'RENEWAL_PAID_OUTSIDE_ALLOWED_DATES'                  WHEN SecondFSBCommissionDetailID IS NOT NULL        
             THEN 'SECOND_HALF_GRANTED'                  ELSE 'VALID_RENEWAL_PAID'             END AS StatusText ,UserName         INTO #ScreenRows
FROM ScreenRows;          
			 -----------------------------------------------------------------------         
			 --4. OUTPUT         --         
			 -- @ShowAllColumns = 1:         
			 --      full technical/debug/tracking result.         --         
			 -- @ShowAllColumns IS NULL or 0:         
			 --      compact UI summary.         ---------------------------------------------------
--------------------          


SELECT                 PromotionID,
    SponsorID,
    SponsorFSB1Start,
    FSB1StartDate,
    FSB1EndDate,
    FSB1ExtStartDate,
    FSB1ExtEndDate,
    --FSB2StartDate,
    --FSB2EndDate,
    --FSB3StartDate,
    --FSB3EndDate,    
	DATEADD(DAY,
    7,
    FSB1StartDate) AS FSB2StartDate,
    DATEADD(DAY
,
    14,
    DATEADD(SECOND,
    -1,
    FSB1StartDate)) AS FSB2EndDate,
    DATEADD(DAY,
    14,
    FSB1StartDate) AS FSB3StartDate,
    DATEADD(DAY,
    21,
    FSB1StartDate) AS FSB3EndDate,
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
	
	INTO #tmpFSBResultScreenRowsFull
FROM #ScreenRows
ORDER BY SponsorID,
    SponsorFSB1Start,
    CASE                     WHEN TrackingFSBType = 'FSB1' THEN 1                     WHEN TrackingFSBType = 'FSB1_EXT' THEN 2                     WHEN TrackingFSBType = 'FSB2' THEN 3                     WHEN TrackingFSBType = 'FSB3' THEN 4                     ELSE 99                 END,
    OrderDate,
    OrderID,
    PromoterID;  


;WITH Ranked AS
(
    SELECT
        SponsorID,
        FSB,
        OrderID,
        PromoterEnrollDate,
        ROW_NUMBER() OVER
        (
            PARTITION BY SponsorID, FSB
            ORDER BY PromoterEnrollDate, OrderID
        ) AS RN
    FROM #tmpFSBResultScreenRowsFull
),
SecondMember AS
(
    SELECT
        SponsorID,
        FSB,
        MAX(PromoterEnrollDate) AS SecondOrderDate
    FROM Ranked
    WHERE RN <= 2
    GROUP BY SponsorID,FSB
    HAVING COUNT(*) = 2
),
SecondMemberDates AS
(
    SELECT
        SponsorID,
        MAX(CASE WHEN FSB='FSB1' THEN SecondOrderDate END) AS FSB1Date,
        MAX(CASE WHEN FSB='FSB1_EXT' THEN SecondOrderDate END) AS FSB1ExtDate,
        MAX(CASE WHEN FSB='FSB2' THEN SecondOrderDate END) AS FSB2Date,
        MAX(CASE WHEN FSB='FSB3' THEN SecondOrderDate END) AS FSB3Date
    FROM SecondMember
    GROUP BY SponsorID
)
UPDATE ft
SET
    FSB1EndDate =
        COALESCE(sm.FSB1Date, ft.FSB1EndDate),

    FSB1ExtStartDate =
        COALESCE(sm.FSB1Date, ft.FSB1ExtStartDate),

    FSB1ExtEndDate =
        COALESCE(sm.FSB1ExtDate, sm.FSB1Date, ft.FSB1ExtEndDate),

    FSB2StartDate =
        COALESCE(sm.FSB1ExtDate, sm.FSB1Date, ft.FSB2StartDate),

    FSB2EndDate =
        COALESCE(sm.FSB2Date, 
		CASE WHEN sm.FSB1ExtDate IS NOT NULL
                      THEN DATEADD(DAY,7,sm.FSB1ExtDate)
                 END,
				 CASE WHEN sm.FSB1Date IS NOT NULL
                      THEN DATEADD(DAY,7,sm.FSB1Date)
                 END, 
				 ft.FSB2EndDate),

    FSB3StartDate =
        COALESCE(sm.FSB2Date, 
			CASE WHEN sm.FSB1ExtDate IS NOT NULL
                      THEN DATEADD(DAY,7,sm.FSB1ExtDate)
                 END,
				 CASE WHEN sm.FSB1Date IS NOT NULL
                      THEN DATEADD(DAY,7,sm.FSB1Date)
                 END, 
				 ft.FSB3StartDate),

    FSB3EndDate =
        COALESCE(sm.FSB3Date,
                 CASE WHEN sm.FSB2Date IS NOT NULL
                      THEN DATEADD(DAY,7,sm.FSB2Date)
                 END,
				 CASE WHEN sm.FSB1ExtDate IS NOT NULL
                      THEN DATEADD(DAY,14,sm.FSB1ExtDate)
                 END,
				 CASE WHEN sm.FSB1Date IS NOT NULL
                      THEN DATEADD(DAY,14,sm.FSB1Date)
                 END,
                 ft.FSB3EndDate)
FROM #tmpFSBResultScreenRowsFull ft
JOIN SecondMemberDates sm
    ON sm.SponsorID = ft.SponsorID;

   

IF ISNULL(@ShowAllColumns,0) = 1         
BEGIN             
	select * from #tmpFSBResultScreenRowsFull;

    END         ELSE         BEGIN      
	   

	   SELECT                 SponsorID,
    SponsorFSB1Start,
    FSB1StartDate,
    FSB1EndDate,
    FSB1ExtStartDate,
    FSB1ExtEndDate,
    FSB2StartDate,
    FSB2EndDate,
    FSB3StartDate,
    FSB3EndDate,     
--	DATEADD(DAY,
--    7,
--    FSB1StartDate) AS FSB2StartDate,
--    DATEADD(DAY,
--    14,
--    DATEADD(SECOND,
--    -1,
--    FSB1StartDate)) AS FSB2EndDate,
--    DATEADD
--(DAY,
--    14,
--    FSB1StartDate) AS FSB3StartDate,
--    DATEADD(DAY,
--    21,
--    FSB1StartDate) AS FSB3EndDate,
	
    FSB,
    Ambassador,
    PromoterEnrollDate AS EnrollDate,
    Product,
    LastPaymentCreateDate AS LastPayment,
	OrderDate,
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
	FROM #tmpFSBResultScreenRowsFull;    



	END;      
	END 
	
	TRY     BEGIN CATCH          DECLARE @ErrorMessage NVARCHAR(4000);         DECLARE @ErrorSeverity INT;         
				 DECLARE @ErrorState INT;          
				 
				 SELECT             @ErrorMessage = ERROR_MESSAGE(),
    @ErrorSeverity = ERROR_SEVERITY(),
    @ErrorState = ERROR_STATE();          RAISERROR(@ErrorMessage,
    @ErrorSeverity,
    @ErrorState);         RETURN;      END CATCH 
	END; 


	--select * from FSBTrackings where SponsorID=@SponsorID