set dateformat ymd

declare @userid int;
declare @year int = 2026
declare @yearStart date = case when @year is null then null else datefromparts(@year, 1, 1) end;
declare @today datetime = getdate()
declare @limit date = cast(dateadd(month, -1, @today) as date)
declare @proname varchar(500) = (select [name] from [product] where [name] = 'Travel Advantage Pro')
declare @elitename varchar(500) = (select [name] from [product] where [name] = 'Travel Advantage Elite')
declare @eliteid varchar(500) = (select productid from [product] where [name] = 'Travel Advantage Elite')
declare @fsb1id int = (select ID from DailyRealTimeCommissionType where Active = 1 and [Type] = 0 and [Description] like '%Fast Start Bonus 1%' and [Description] like '%2nd Half%')
declare @fsb2id int = (select ID from DailyRealTimeCommissionType where Active = 1 and [Type] = 0 and [Description] like '%Fast Start Bonus 2%' and [Description] like '%2nd Half%')
declare @fsb3id int = (select ID from DailyRealTimeCommissionType where Active = 1 and [Type] = 0 and [Description] like '%Fast Start Bonus 3%' and [Description] like '%2nd Half%')
declare @fsb1 nvarchar(50) = (select [description] from DailyRealTimeCommissionType where id = @fsb1id)
declare @fsb2 nvarchar(50) = (select [description] from DailyRealTimeCommissionType where id = @fsb2id)
declare @fsb3 nvarchar(50) = (select [description] from DailyRealTimeCommissionType where id = @fsb3id)

--select @fsb1, @fsb1id, @fsb2, @fsb2id, @fsb3, @fsb3id

drop table if exists #tmp_al_fsb_paid_resume;
drop table if exists #tmp_al_fsb_to_be_paid;
drop table if exists #tmp_al_candidate_sponsors;
drop table if exists #tmp_al_direct_enrollments_resume;
drop table if exists #tmp_al_final_transactions_table;
drop table if exists #tmp_al_transactions_resume;

IF OBJECT_ID('tempdb..#tmp_al_final_transactions_table') IS NOT NULL DROP TABLE #tmp_al_final_transactions_table;
CREATE TABLE #tmp_al_final_transactions_table (
    transactionid int,
	transactiontype varchar(500),
	userid int,
	promoterid int,
	customerid int,
	orderid int,
	spreedlysubscriberid int,
	billinginfoid int,
	createdate datetime,
	username varchar(max),
	membername varchar(max),
	email varchar(max), 
	amount money, 
	[description] varchar(max), 
	Gateway varchar(max),
	GuestPassUsed varchar(max),
	TokenUsed varchar(250),
	tokentype varchar(500),
	couponused varchar(250),
	coupontype varchar(500),
	IsAmbassador bit,
	[service] varchar(max), 
	turbo bit,
	IsPromoCouponApplied bit,
	ispermanentpromocouponapplied bit,
	specialpromo bit,
	FreeCommission bit
);

;with fsb_paid as (
	select com.id, tp.[description] as commissiontype, u.userid, p.PromoterId, u.username, concat(u.firstname, ' ', u.lastname) as membername, p.EnrollDate,
	com.Amount, com.[Description], com.EarnedDate, com.PaymentDate, com.Paid, com.[type], com.creation
	from DailyRealTimeCommission com
	inner join DailyRealTimeCommissionType tp on tp.ID = com.CommissionTypeID
	inner join Promoters p on p.promoterid = com.promoterid
	inner join userprofile u on u.userid = p.userprofileid
	where tp.[description] like '%Fast Start%'
	and tp.active = 1
	and tp.[type] = 0
	and (@userid is null or @userid = u.userid)
),

reversals as (
	select com.id, tp.[description] as commissiontype, u.userid, p.PromoterId, u.username, concat(u.firstname, ' ', u.lastname) as membername, p.EnrollDate, 
	com.Amount, com.[Description], com.EarnedDate, com.PaymentDate, com.Paid, com.[type], com.creation, com.ReversalTransactionID
	from DailyRealTimeCommission com
	inner join DailyRealTimeCommissionType tp on tp.ID = com.CommissionTypeID
	inner join Promoters p on p.promoterid = com.promoterid
	inner join userprofile u on u.userid = p.userprofileid
	where ((tp.[description] like '%Fast Start%' and tp.active = 1 and tp.[type] = 1)
	or (
		tp.[description] like '%Admin%' 
		and 
		com.Amount < 0 
		and 
		(com.[Description] like '%Fast%' or com.[Description] like '%FSB%') 
		and 
		com.[Description] not like '%Tokens:%'
		and
		com.[Description] not like '%Token%')
	)
	and (@userid is null or @userid = u.userid)
),

fsb_paid_resume as (
	select fsb.*
	from fsb_paid fsb
	left join reversals r on r.ReversalTransactionID = fsb.ID
	left join reversals r0 on r0.ReversalTransactionID = 0 and r0.UserId = fsb.userid and r0.EarnedDate >= fsb.EarnedDate
	where r.ID is null
	and r0.ID is null
)

select *
into #tmp_al_fsb_paid_resume
from fsb_paid_resume;

CREATE CLUSTERED INDEX IX_tmp_al_fsb_paid_resume_user_earned
ON #tmp_al_fsb_paid_resume (userid, earneddate, id);

CREATE NONCLUSTERED INDEX IX_tmp_al_fsb_paid_resume_type
ON #tmp_al_fsb_paid_resume (commissiontype, earneddate)
INCLUDE (userid, promoterid, amount);

;with first_half as (
	select 
		f1.UserId, 
		f1.PromoterId, 
		f1.UserName, 
		f1.membername, 
		f1.enrolldate, 
		f1.ID, 
		f1.commissiontype, 
		f1.Amount, 
		f1.[Description], 
		f1.EarnedDate, 
		f1.PaymentDate, 
		f1.Paid, 
		f1.[Type], 
		f1.Creation,

		case
			when f1.commissiontype like '%Fast Start Bonus 1%' then 1
			when f1.commissiontype like '%Fast Start Bonus 2%' then 2
			when f1.commissiontype like '%Fast Start Bonus 3%' then 3
		end as first_half_fsb_no

	from #tmp_al_fsb_paid_resume f1
	where (@yearStart is null or f1.earneddate >= @yearStart)
	and (@limit is null or f1.EarnedDate <= @limit)
	and f1.commissiontype not like '%2nd Half%'
	and (
		f1.commissiontype like '%Fast Start Bonus 1%'
		or f1.commissiontype like '%Fast Start Bonus 2%'
		or f1.commissiontype like '%Fast Start Bonus 3%'
	)
	and not exists (
		select 1
		from #tmp_al_fsb_paid_resume f2
		where f2.userid = f1.userid
		and f2.EarnedDate > f1.EarnedDate
		and (@yearStart is null or f2.earneddate >= @yearStart)
		and (
			f2.commissiontype like '%2nd Half%'
			or f2.[Description] like '%Second%'
			or f2.[Description] like '%econd%'
			or f2.[Description] like '%2nd%'
			or f2.[Description] like '%Part 2%'
		)
		and (
			(
				f1.commissiontype like '%Fast Start Bonus 1%'
				and (
					f2.commissiontype like '%Fast Start Bonus 1%'
					or f2.[Description] like '%Fast Start Bonus 1%'
					or f2.[Description] like '%FSB1%'
				)
			)
			or
			(
				f1.commissiontype like '%Fast Start Bonus 2%'
				and (
					f2.commissiontype like '%Fast Start Bonus 2%'
					or f2.[Description] like '%Fast Start Bonus 2%'
					or f2.[Description] like '%FSB2%'
				)
			)
			or
			(
				f1.commissiontype like '%Fast Start Bonus 3%'
				and (
					f2.commissiontype like '%Fast Start Bonus 3%'
					or f2.[Description] like '%Fast Start Bonus 3%'
					or f2.[Description] like '%FSB3%'
				)
			)
		)
	)
)

select *
into #tmp_al_fsb_to_be_paid
from first_half;

CREATE CLUSTERED INDEX IX_tmp_al_fsb_to_be_paid_user_promoter
ON #tmp_al_fsb_to_be_paid (userid, promoterid, earneddate, id);

CREATE NONCLUSTERED INDEX IX_tmp_al_fsb_to_be_paid_fsb
ON #tmp_al_fsb_to_be_paid (commissiontype, earneddate)
INCLUDE (userid, promoterid, username, membername, amount, enrolldate);

IF OBJECT_ID('tempdb..#tmp_al_candidate_sponsors') IS NOT NULL DROP TABLE #tmp_al_candidate_sponsors;

select
	tbp.ID as first_half_commission_id,
	tbp.UserId as sponsoruserid,
	tbp.PromoterId as sponsorid,
	tbp.UserName as sponsorusername,
	tbp.membername as sponsorname,
	tbp.EnrollDate as sponsorenrolldate,
	tbp.commissiontype,
	tbp.Amount,
	tbp.[Description],
	tbp.EarnedDate,
	tbp.PaymentDate,
	tbp.Paid,
	tbp.[Type],
	tbp.Creation,

	case
		when tbp.commissiontype like '%Fast Start Bonus 1%' then 1
		when tbp.commissiontype like '%Fast Start Bonus 2%' then 2
		when tbp.commissiontype like '%Fast Start Bonus 3%' then 3
	end as first_half_fsb_no,

	case 
		when cast(tbp.EarnedDate as date) <= cast(dateadd(day, 21, tbp.EnrollDate) as date)
			then 1
		else 0
	end as is_standard_fsb,

	case 
		when cast(tbp.EarnedDate as date) <= cast(dateadd(day, 21, tbp.EnrollDate) as date)
			then null
		else dateadd(day, -7, cast(tbp.EarnedDate as date))
	end as promo_window_start,

	case 
		when cast(tbp.EarnedDate as date) <= cast(dateadd(day, 21, tbp.EnrollDate) as date)
			then null
		else cast(tbp.EarnedDate as date)
	end as promo_window_end
into #tmp_al_candidate_sponsors
from #tmp_al_fsb_to_be_paid tbp
where tbp.commissiontype like '%Fast Start Bonus 1%'
or tbp.commissiontype like '%Fast Start Bonus 2%'
or tbp.commissiontype like '%Fast Start Bonus 3%';

CREATE CLUSTERED INDEX IX_tmp_al_candidate_sponsors_main
ON #tmp_al_candidate_sponsors (sponsoruserid, sponsorid, first_half_commission_id);

CREATE NONCLUSTERED INDEX IX_tmp_al_candidate_sponsors_dates
ON #tmp_al_candidate_sponsors (is_standard_fsb, EarnedDate, sponsorenrolldate)
INCLUDE (sponsoruserid, sponsorid, first_half_commission_id, first_half_fsb_no, promo_window_start, promo_window_end);

;with direct_enrollments as (
	select 
		e.UserId, 
		e.CustomerID, 
		e.promoterid, 
		e.UserName, 
		e.membername, 
		e.enrolldate, 
		ord.OrderID, 
		ord.[status] as orderstatus,
		case 
			when ord.IsEliteTravelAdvantagePro = 1 and prod.[Name] = @proname then @elitename 
			else prod.[Name] 
		end as servicename,
		e.sponsoruserid,
		e.sponsorid
	from (
		select 
			u.userid, 
			cust.customerid, 
			isnull(p.promoterid, 0) as promoterid, 
			u.username, 
			concat(u.firstname, ' ', u.lastname) as membername, 
			isnull(p.enrolldate, cust.enrolldate) as enrolldate,
			case when p.promoterid is null then cust.SponsorMemberID else upsp.UserId end as sponsoruserid,
			case when p.promoterid is null then pcsp.promoterid else psp.promoterid end as sponsorid
		from UserProfile u
		inner join MWRCustomers cust 
			on cust.userid = u.userid
		left join Promoters p 
			on p.userprofileid = u.userid
		left join Promoters psp 
			on psp.promoterid = p.SponsorId
		left join UserProfile upsp 
			on upsp.UserId = psp.UserProfileId
		left join Promoters pcsp 
			on pcsp.UserProfileId = cust.SponsorMemberID
		where u.applicationname = 'mwrlife.com'
		and exists (
			select 1
			from #tmp_al_candidate_sponsors cs
			where cs.sponsoruserid = case when p.promoterid is null then cust.SponsorMemberID else upsp.UserId end
			and cs.sponsorid = case when p.promoterid is null then pcsp.promoterid else psp.promoterid end
		)
	) e
	inner join [Order] ord 
		on ord.CustomerId = e.CustomerID
	inner join [Product] prod 
		on prod.ProductID = ord.ProductID
	where prod.[Name] like '%Travel Advantage%'
),

direct_enrollments_resume as (
	select 
		de.UserId, 
		de.CustomerID, 
		de.promoterid, 
		de.UserName, 
		de.membername, 
		de.enrolldate, 
		de.OrderID, 
		de.orderstatus, 
		de.servicename,

		cs.sponsoruserid,
		cs.sponsorid,
		cs.sponsorusername,
		cs.sponsorname,
		cs.sponsorenrolldate,

		cs.first_half_commission_id,
		cs.commissiontype,
		cs.Amount,
		cs.[Description],
		cs.EarnedDate,
		cs.PaymentDate,
		cs.Paid,
		cs.[Type],
		cs.Creation,
		cs.first_half_fsb_no,
		cs.is_standard_fsb,
		cs.promo_window_start,
		cs.promo_window_end

	from direct_enrollments de
	inner join #tmp_al_candidate_sponsors cs
		on cs.sponsoruserid = de.sponsoruserid
		and cs.sponsorid = de.sponsorid
	where 
	(
		cs.is_standard_fsb = 1
		and de.enrolldate >= cs.sponsorenrolldate
		and de.enrolldate <= dateadd(day, 21, cs.sponsorenrolldate)
	)
	or
	(
		cs.is_standard_fsb = 0
		and cast(de.enrolldate as date) >= cs.promo_window_start
		and cast(de.enrolldate as date) <= cs.promo_window_end
	)
)

select *
into #tmp_al_direct_enrollments_resume
from direct_enrollments_resume;

CREATE CLUSTERED INDEX IX_tmp_al_direct_enrollments_resume_user_order
ON #tmp_al_direct_enrollments_resume (UserId, OrderID, first_half_commission_id);

CREATE NONCLUSTERED INDEX IX_tmp_al_direct_enrollments_resume_sponsor
ON #tmp_al_direct_enrollments_resume (sponsoruserid, sponsorid, first_half_commission_id)
INCLUDE (enrolldate, customerid, orderid, first_half_fsb_no, is_standard_fsb);

insert into #tmp_al_final_transactions_table(transactionid, transactiontype, spreedlysubscriberid, billinginfoid, createdate, amount, [description], gateway, 
	orderid, userid, customerid, promoterid, username, membername, email, isambassador, guestpassused, tokenused, couponused, coupontype)
select 
	t.transactionid,
	tt.[Description] as transactiontype,
	t.SpreedlySubscriberId,
	t.BiIlingInfoId,
	t.CreateDate,
	t.amount,
	t.[description], 
	t.Gateway,
	o.orderid as orderid,
	up.userid,
	m.customerid,
	p.promoterid,
	up.username,
	case 
		when up.username is null then null
		else concat(up.firstname, ' ', up.lastname) 
	end as membername,
	up.email as email,
	isnull(up.ispromoter, 'false') as isambassador,
	CASE WHEN t.ExternalTransactionID like '% - CODE: %' THEN t.ExternalTransactionID END AS GuestPassUsed,
	REPLACE((CASE WHEN t.ExternalTransactionID like '%Token: %' or LEN(t.ExternalTransactionID) = 7 THEN t.externalTransactionID END), 'Token: ', '') as TokenUsed,
	cp.CouponCode as couponused,
	ct.[Description] as coupontype
from [Transaction] t
left join transactiontype tt on tt.Id = t.TransactionType
inner join SpreedlySubscriber ss on t.SpreedlySubscriberId = ss.Id 
inner join [order] o on ss.OrderId = o.OrderID 
inner join MWRCustomers m on o.CustomerId = m.CustomerID 
inner join UserProfile up on m.UserID = up.UserId
left join promoters p on p.userprofileid = up.userid
left join Coupons cp on cp.CouponId = o.couponid
left join CouponsTypes ct on ct.CouponTypeID = cp.CouponTypeID
inner join #tmp_al_direct_enrollments_resume e on e.UserId = up.userid and e.OrderID = o.orderid
where t.Success = 1
and up.applicationname = 'mwrlife.com'

insert into #tmp_al_final_transactions_table(transactionid, transactiontype, spreedlysubscriberid, billinginfoid, createdate, amount, [description], gateway, 
	orderid, userid, customerid, promoterid, username, membername, email, isambassador, guestpassused, tokenused)
select 
	t.transactionid,
	tt.[Description] as transactiontype,
	t.SpreedlySubscriberId,
	t.BiIlingInfoId,
	t.CreateDate,
	t.amount,
	t.[description], 
	t.Gateway,
	null as orderid,
	up2.userid,
	m2.customerid,
	p2.promoterid,
	up2.username,
	case 
		when up2.username is null then null
		else concat(up2.firstname, ' ', up2.lastname) 
	end as membername,
	up2.email,
	up2.ispromoter as isambassador,
	CASE WHEN t.ExternalTransactionID like '% - CODE: %' THEN t.ExternalTransactionID END AS GuestPassUsed,
	REPLACE((CASE WHEN t.ExternalTransactionID like '%Token: %' or LEN(t.ExternalTransactionID) = 7 THEN t.externalTransactionID END), 'Token: ', '') as TokenUsed
from [Transaction] t
left join transactiontype tt on tt.Id = t.TransactionType
inner join BillingInfo b on t.BiIlingInfoId = b.CollectionId 
inner join Promoters p2 on b.PromoterId = p2.promoterid
inner join UserProfile up2 on p2.userprofileid = up2.UserId 
inner join MWRCustomers m2 on up2.userid = m2.UserID 
inner join #tmp_al_direct_enrollments_resume e on e.UserId = up2.userid
where t.Success = 1
and up2.applicationname = 'mwrlife.com';

CREATE CLUSTERED INDEX IX_tmp_al_final_transactions_table_main
ON #tmp_al_final_transactions_table (userid, orderid, createdate, transactionid);

CREATE NONCLUSTERED INDEX IX_tmp_al_final_transactions_table_customer
ON #tmp_al_final_transactions_table (customerid, orderid)
INCLUDE (userid, createdate, amount, transactiontype, [service]);

CREATE NONCLUSTERED INDEX IX_tmp_al_final_transactions_table_service
ON #tmp_al_final_transactions_table (transactiontype, amount, userid, orderid)
INCLUDE (customerid, createdate, turbo, FreeCommission);

update t
set [service] = case when prod.[name] = @proname and o.IsEliteTravelAdvantagePro = 1 then @elitename else prod.[name] end,
turbo = o.turbo,
IsPromoCouponApplied = o.IsPromoCouponApplied,
ispermanentpromocouponapplied = o.ispermanentpromocouponapplied,
specialpromo = o.IsCreatedWithPromoPrice,
FreeCommission = o.FreeCommission
from #tmp_al_final_transactions_table t
inner join [order] o on t.OrderId = o.OrderID 
inner join [product] prod on prod.ProductID = o.ProductID
left join OrderProductHistory oph on oph.orderid = t.orderid
where isnull(t.orderid, 0) <> 0
and oph.ID is null

update t
set [service] = tr.[service],
turbo = tr.turbo,
IsPromoCouponApplied = tr.IsPromoCouponApplied,
ispermanentpromocouponapplied = tr.ispermanentpromocouponapplied,
specialpromo = tr.specialpromo,
FreeCommission = tr.FreeCommission
from (
	select
	t.transactionid,
	cp.couponcode as couponused,
	ct.[description] as coupontype,
	case when prod.[name] = @proname and oph.iseliteupgrade = 1 then @elitename else prod.[name] end as [service],
	o.turbo,
	o.IsPromoCouponApplied,
	o.ispermanentpromocouponapplied,
	o.IsCreatedWithPromoPrice as specialpromo,
	o.FreeCommission,
	ROW_NUMBER() OVER(PARTITION BY t.orderid ORDER BY oph.creationdate DESC) AS rn
	from #tmp_al_final_transactions_table t
	inner join [order] o on o.orderid = t.orderid
	inner join orderproducthistory oph on oph.orderid = o.orderid
	inner join [product] prod on prod.productid = oph.NewProductID
	left join coupons cp on cp.couponid = o.couponid
	left join CouponsTypes ct on ct.CouponTypeID = cp.coupontypeid
	where t.[service] is null
	and t.createdate >= oph.CreationDate
) tr
inner join #tmp_al_final_transactions_table t on t.transactionid = tr.transactionid
where rn = 1

update t
set [service] = case tr.[service] when @proname then @elitename else tr.[service] end,
turbo = tr.turbo,
IsPromoCouponApplied = tr.IsPromoCouponApplied,
ispermanentpromocouponapplied = tr.ispermanentpromocouponapplied,
specialpromo = tr.specialpromo,
FreeCommission = tr.FreeCommission,
orderid = tr.orderid
from (
	select
	t.transactionid,
	o.orderid,
	cp.couponcode as couponused,
	ct.[description] as coupontype,
	case when isnull(prod2.[name], prod.[name]) = @proname and isnull(oph.iseliteupgrade, o.IsEliteTravelAdvantagePro) = 1 then @elitename else isnull(prod2.[name], prod.[name]) end as [service],
	o.turbo,
	o.IsPromoCouponApplied,
	o.ispermanentpromocouponapplied,
	o.IsCreatedWithPromoPrice as specialpromo,
	o.FreeCommission,
	ROW_NUMBER() OVER(PARTITION BY t.orderid ORDER BY oph.creationdate DESC) AS rn
	from #tmp_al_final_transactions_table t
	inner join [order] o on o.customerid = t.customerid
	left join orderproducthistory oph on oph.orderid = o.orderid
	inner join [product] prod on prod.productid = o.productid
	left join [product] prod2 on prod2.productid = oph.NewProductID
	left join coupons cp on cp.couponid = o.couponid
	left join CouponsTypes ct on ct.CouponTypeID = cp.coupontypeid
	where t.transactiontype like '%Enrollment%'
	and t.orderid is null
	and prod.[name] like '%Travel Advantage%'
	and (t.createdate >= isnull(oph.creationdate, o.CreateDate) or dateadd(ms, 500, t.createdate) >= isnull(oph.creationdate, o.CreateDate))
) tr
inner join #tmp_al_final_transactions_table t on t.transactionid = tr.transactionid
where rn = 1

update t2
set [service] = t.[service],
turbo = t.turbo,
IsPromoCouponApplied = t.IsPromoCouponApplied,
ispermanentpromocouponapplied = t.ispermanentpromocouponapplied,
specialpromo = t.specialpromo,
FreeCommission = t.FreeCommission,
orderid = t.orderid
from #tmp_al_final_transactions_table t
inner join #tmp_al_final_transactions_table t2 on t2.userid = t.userid and t2.createdate = t.createdate
where t.transactiontype like '%Enrollment%'
and t2.transactiontype = 'Terms Accepted'
and t2.[service] is null

update t
set [service] = @elitename,
turbo = o.turbo, 
ispromocouponapplied = o.IsPromoCouponApplied, 
IsPermanentPromoCouponApplied = o.IsPermanentPromoCouponApplied, 
specialpromo = o.IsCreatedWithPromoPrice, 
freecommission = o.FreeCommission,
orderid = case 
	when oph.id is null and (t.createdate >= o.CreateDate or dateadd(ms, 500, t.createdate) >= o.CreateDate) and prod.[name] in (@proname, @elitename) then o.orderid
	else oph.orderid
end
from #tmp_al_final_transactions_table t
inner join [order] o on o.customerid = t.customerid
left join OrderProductHistory oph on oph.orderid = o.orderid
inner join [product] prod on prod.productid = o.productid
left join [product] prod2 on prod2.productid = oph.NewProductID
left join [product] prod3 on prod3.productid = oph.PreviousProductID
where [service] is null 
and t.transactiontype = 'Enrollment Elite'
and (prod.[name] in (@proname, @elitename) or prod2.[name] in (@proname, @elitename) or prod3.[name] in (@proname, @elitename))
and (
		(
			oph.id is null 
			and (t.createdate >= o.CreateDate or dateadd(ms, 500, t.createdate) >= o.CreateDate)
			and prod.[name] in (@proname, @elitename)
		)
		or
		(
			oph.id is not null 
			and (t.createdate >= oph.creationdate or dateadd(ms, 500, t.createdate) >= oph.creationdate)
			and prod2.[name] in (@proname, @elitename)
		)
		or
		(
			oph.id is not null 
			and dateadd(ms, 500, t.createdate) < oph.creationdate
			and prod3.[name] in (@proname, @elitename)
		)
	)

update t2
set [service] = t.[service],
turbo = t.turbo,
IsPromoCouponApplied = t.IsPromoCouponApplied,
ispermanentpromocouponapplied = t.ispermanentpromocouponapplied,
specialpromo = t.specialpromo,
FreeCommission = t.FreeCommission,
orderid = t.orderid
from #tmp_al_final_transactions_table t
inner join #tmp_al_final_transactions_table t2 on t2.userid = t.userid and t2.createdate = t.createdate
where t.transactiontype = 'Enrollment Elite'
and t2.transactiontype = 'Terms Accepted'
and t2.[service] is null

update t
set [service] = prod.[name],
turbo = o.turbo,
IsPromoCouponApplied = o.IsPromoCouponApplied,
ispermanentpromocouponapplied = o.ispermanentpromocouponapplied,
specialpromo = o.IsCreatedWithPromoPrice,
FreeCommission = o.FreeCommission,
orderid = o.orderid
from #tmp_al_final_transactions_table t
inner join [order] o on o.customerid = t.customerid
inner join [product] prod on prod.productid = o.productid
where [service] is null 
and t.transactiontype = 'BizCenter Fee MWRLife'
and prod.[name] like '%App Subscription%'

update t
set orderid = isnull(t.orderid, o2.orderid), 
[service] = prod.[name], 
turbo = isnull(o.turbo, o2.turbo),
ispromocouponapplied = isnull(o.IsPromoCouponApplied, o2.IsPromoCouponApplied),
ispermanentpromocouponapplied = isnull(o.ispermanentpromocouponapplied, o2.ispermanentpromocouponapplied),
specialpromo = isnull(o.IsCreatedWithPromoPrice, o2.IsCreatedWithPromoPrice),
FreeCommission = isnull(o.FreeCommission, o2.FreeCommission)
from #tmp_al_final_transactions_table t
left join [order] o on o.orderid = t.orderid
left join [order] o2 on o2.customerid = t.customerid
left join [product] prod2 on prod2.productid = o2.productid and prod2.[name] like '%Travel Advantage%'
inner join [product] prod on prod.[name] = REPLACE(t.transactiontype, '™', '') 
where t.[service] is null

update t2
set [service] = t.[service],
turbo = t.turbo,
IsPromoCouponApplied = t.IsPromoCouponApplied,
ispermanentpromocouponapplied = t.ispermanentpromocouponapplied,
specialpromo = t.specialpromo,
FreeCommission = t.FreeCommission,
orderid = t.orderid
from #tmp_al_final_transactions_table t
inner join #tmp_al_final_transactions_table t2 on t2.userid = t.userid and t2.createdate = t.createdate
where t.transactiontype like '%Enrollment'
and t2.transactiontype = 'Terms Accepted'
and t2.[service] is null

;with ctr as (
	select t.transactionid, t.userid, count(distinct o.orderid) as ctr 
	from #tmp_al_final_transactions_table t
	inner join [order] o on o.customerid = t.customerid
	inner join [product] prod on prod.productid = o.productid and prod.[name] like '%Travel Advantage%'
	left join orderproducthistory oph on oph.orderid = o.orderid
	where t.[service] is null 
	and oph.id is null
	group by t.transactionid, t.userid
)

update t
set orderid = o.orderid, 
[service] = case when (o.IsEliteTravelAdvantagePro = 1 and prod.[name] = @proname) then @elitename else prod.[name] end, 
turbo = o.turbo,
ispromocouponapplied = o.IsPromoCouponApplied,
ispermanentpromocouponapplied = o.ispermanentpromocouponapplied,
specialpromo = o.IsCreatedWithPromoPrice,
FreeCommission = o.FreeCommission
from #tmp_al_final_transactions_table t
inner join [order] o on o.customerid = t.customerid
inner join [product] prod on prod.productid = o.productid and prod.[name] like '%Travel Advantage%'
left join orderproducthistory oph on oph.orderid = o.orderid
inner join ctr on ctr.transactionid = t.transactionid and t.userid = ctr.userid
where t.[service] is null 
and oph.id is null
and ctr.ctr = 1

update t
set orderid = tr.orderid, 
[service] = tr.[service], 
turbo = tr.turbo,
ispromocouponapplied = tr.IsPromoCouponApplied,
ispermanentpromocouponapplied = tr.ispermanentpromocouponapplied,
specialpromo = tr.IsCreatedWithPromoPrice,
FreeCommission = tr.FreeCommission
from (
	select distinct t.transactionid, o.orderid, oph.CreationDate, t.createdate, 
	case when dateadd(millisecond, 500, t.createdate) >= oph.creationdate then case when (oph.IsEliteUpgrade = 1 and np.[name] = @proname) or (o.IsEliteTravelAdvantagePro = 1 and prod.[name] = @proname) then @elitename else np.[name] end else pp.[name] end as [service],
	ROW_NUMBER() OVER(PARTITION BY t.transactionid, t.orderid ORDER BY oph.creationdate DESC) AS rn,
	o.turbo, o.IsPromoCouponApplied, o.IsPermanentPromoCouponApplied, o.IsCreatedWithPromoPrice, o.FreeCommission
	from #tmp_al_final_transactions_table t
	inner join [order] o on o.customerid = t.customerid
	inner join [product] prod on prod.productid = o.productid and prod.[name] like '%Travel Advantage%'
	inner join orderproducthistory oph on oph.orderid = o.orderid
	inner join [product] pp on pp.productid = oph.PreviousProductID
	inner join [product] np on np.productid = oph.NewProductID
	where t.[service] is not null
	and (prod.[name] like '%Travel Advantage%' or prod.[name] like '%App Subscription%')
) tr
inner join #tmp_al_final_transactions_table t on t.transactionid = tr.transactionid
where tr.rn = 1

update t
set orderid = tr.orderid, 
[service] = tr.[service], 
turbo = tr.turbo,
ispromocouponapplied = tr.IsPromoCouponApplied,
ispermanentpromocouponapplied = tr.ispermanentpromocouponapplied,
specialpromo = tr.IsCreatedWithPromoPrice,
FreeCommission = tr.FreeCommission
from (
	select distinct 
		t.transactionid, o.orderid, oph.CreationDate, t.createdate, 
		case when dateadd(millisecond, 500, t.createdate) >= oph.creationdate then case when (oph.IsEliteUpgrade = 1 and np.[name] = @proname) or (o.IsEliteTravelAdvantagePro = 1 and prod.[name] = @proname) then @elitename else np.[name] end else pp.[name] end as [service],
		o.turbo, o.IsPromoCouponApplied, o.IsPermanentPromoCouponApplied, o.IsCreatedWithPromoPrice, o.FreeCommission,
		ROW_NUMBER() OVER(PARTITION BY t.transactionid, t.orderid ORDER BY oph.creationdate DESC) AS rn
	from #tmp_al_final_transactions_table t
	inner join [order] o on o.orderid = t.orderid
	inner join [product] prod on prod.productid = o.ProductID
	left join OrderProductHistory oph on oph.orderid = o.orderid
	left join [product] pp on pp.productid = oph.PreviousProductID
	left join [product] np on np.productid = oph.NewProductID
	where [service] is null
	and (prod.[name] like '%Travel Advantage%' or prod.[name] like '%App Subscription%')
) tr
inner join #tmp_al_final_transactions_table t on t.transactionid = tr.transactionid
where tr.rn = 1

update t
set orderid = tr.orderid, 
[service] = tr.[service], 
turbo = tr.turbo,
ispromocouponapplied = tr.IsPromoCouponApplied,
ispermanentpromocouponapplied = tr.ispermanentpromocouponapplied,
specialpromo = tr.IsCreatedWithPromoPrice,
FreeCommission = tr.FreeCommission
from (
	select distinct t.transactionid, o.orderid, oph.CreationDate, t.createdate, 
		case when dateadd(millisecond, 500, t.createdate) >= oph.creationdate then case when (oph.IsEliteUpgrade = 1 and np.[name] = @proname) or (o.IsEliteTravelAdvantagePro = 1 and prod.[name] = @proname) then @elitename else np.[name] end else pp.[name] end as [service],
		o.turbo, o.IsPromoCouponApplied, o.IsPermanentPromoCouponApplied, o.IsCreatedWithPromoPrice, o.FreeCommission,
		ROW_NUMBER() OVER(PARTITION BY t.transactionid, t.orderid ORDER BY oph.creationdate DESC) AS rn
	from #tmp_al_final_transactions_table t
	inner join [order] o on o.customerid = t.customerid
	inner join [product] prod on prod.productid = o.ProductID
	inner join OrderProductHistory oph on oph.orderid = o.orderid
	inner join [product] pp on pp.productid = oph.PreviousProductID
	inner join [product] np on np.productid = oph.NewProductID
	where [service] is null
	and (prod.[name] like '%Travel Advantage%' or prod.[name] like '%App Subscription%')
) tr
inner join #tmp_al_final_transactions_table t on t.transactionid = tr.transactionid
where tr.rn = 1

update t
set orderid = tr.orderid, 
[service] = tr.[service], 
turbo = tr.turbo,
ispromocouponapplied = tr.IsPromoCouponApplied,
ispermanentpromocouponapplied = tr.ispermanentpromocouponapplied,
specialpromo = tr.IsCreatedWithPromoPrice,
FreeCommission = tr.FreeCommission
from (
	select distinct t.transactionid, o.orderid, t.createdate, 
		case when o.IsEliteTravelAdvantagePro = 1 and prod.[name] = @proname then @elitename else prod.[name] end as [service],
		o.turbo, o.IsPromoCouponApplied, o.IsPermanentPromoCouponApplied, o.IsCreatedWithPromoPrice, o.FreeCommission,
		ROW_NUMBER() OVER(PARTITION BY t.transactionid, t.orderid ORDER BY o.orderdate DESC) AS rn
	from #tmp_al_final_transactions_table t
	inner join [order] o on o.customerid = t.customerid
	inner join [product] prod on prod.productid = o.ProductID
	where [service] is null 
	and dateadd(millisecond, 500, t.createdate) >= o.createdate
	and (prod.[name] like '%Travel Advantage%' or prod.[name] like '%App Subscription%')
) tr
inner join #tmp_al_final_transactions_table t on t.transactionid = tr.transactionid
where tr.rn = 1

update t
set orderid = tr.orderid, 
[service] = tr.[service], 
turbo = tr.turbo,
ispromocouponapplied = tr.IsPromoCouponApplied,
ispermanentpromocouponapplied = tr.ispermanentpromocouponapplied,
specialpromo = tr.IsCreatedWithPromoPrice,
FreeCommission = tr.FreeCommission
from (
	select distinct t.transactionid, o.orderid, t.createdate, 
		case when o.IsEliteTravelAdvantagePro = 1 and prod.[name] = @proname then @elitename else prod.[name] end as [service],
		o.turbo, o.IsPromoCouponApplied, o.IsPermanentPromoCouponApplied, o.IsCreatedWithPromoPrice, o.FreeCommission,
		ROW_NUMBER() OVER(PARTITION BY t.transactionid, t.orderid ORDER BY o.orderdate DESC) AS rn
	from #tmp_al_final_transactions_table t
	inner join [order] o on o.customerid = t.customerid
	inner join [product] prod on prod.productid = o.ProductID
	where [service] is null
	and (prod.[name] like '%Travel Advantage%' or prod.[name] like '%App Subscription%')
) tr
inner join #tmp_al_final_transactions_table t on t.transactionid = tr.transactionid
where tr.rn = 1

update t
set orderid = tr.orderid, 
[service] = tr.[service], 
turbo = tr.turbo,
ispromocouponapplied = tr.IsPromoCouponApplied,
ispermanentpromocouponapplied = tr.ispermanentpromocouponapplied,
specialpromo = tr.IsCreatedWithPromoPrice,
FreeCommission = tr.FreeCommission
from (
	select distinct t.transactionid, o.orderid, t.createdate, 
		case when o.IsEliteTravelAdvantagePro = 1 and prod.[name] = @proname then @elitename else prod.[name] end as [service],
		o.turbo, o.IsPromoCouponApplied, o.IsPermanentPromoCouponApplied, o.IsCreatedWithPromoPrice, o.FreeCommission,
		ROW_NUMBER() OVER(PARTITION BY t.transactionid, t.orderid ORDER BY prod.[name] DESC, o.createdate desc) AS rn
	from #tmp_al_final_transactions_table t
	inner join [order] o on o.customerid = t.customerid
	inner join [product] prod on prod.productid = o.ProductID
	where [service] not like '%Travel Advantage%'
	and [service] not like '%App Subscription%'
	and (prod.[name] like '%Travel Advantage%' or prod.[name] like '%App Subscription%')
) tr
inner join #tmp_al_final_transactions_table t on t.transactionid = tr.transactionid
where tr.rn = 1

update t
set t.tokentype = tt.tokentypename,
t.coupontype = ct.[description],
t.couponused = cp.couponcode
from #tmp_al_final_transactions_table t
left join TokenTracking tk on tk.TokenCode = t.tokenused
left join TokenType tt on tt.ID = tk.TokenTypeID
left join [order] o on o.orderid = t.orderid
left join Coupons cp on cp.CouponCode = o.CouponCode
left join CouponsTypes ct on ct.CouponTypeID = cp.CouponTypeID

update t
set t.[service] = @elitename,
t.freecommission = case when t.amount = 99.00 then 1 else 0 end,
t.turbo = o.turbo
from #tmp_al_final_transactions_table t
inner join [order] o on o.orderid = t.orderid
where transactiontype = 'Enrollment Elite'

update t
set t.[service] = prod.[name],
turbo = o.turbo,
ispromocouponapplied = o.IsPromoCouponApplied,
ispermanentpromocouponapplied = o.ispermanentpromocouponapplied,
specialpromo = o.IsCreatedWithPromoPrice,
FreeCommission = o.FreeCommission
from #tmp_al_final_transactions_table t
inner join [product] prod on prod.price = t.amount
inner join [order] o on o.orderid = t.orderid
where transactiontype <> 'Enrollment Elite'
and transactiontype like '%Enrollment%'
and t.amount = 19.97
and prod.[name] like '%Travel Advantage%'

update ta
set ta.[service] = e.[service],
ta.turbo = e.turbo,
ta.ispromocouponapplied = e.IsPromoCouponApplied,
ta.ispermanentpromocouponapplied = e.ispermanentpromocouponapplied,
ta.specialpromo = e.specialpromo,
ta.FreeCommission = e.FreeCommission
from #tmp_al_final_transactions_table e
inner join #tmp_al_final_transactions_table ta on ta.userid = e.userid and ta.orderid = e.orderid
where e.transactiontype like '%Enrollment%'
and ta.transactiontype like '%Terms Accepted%'
and datediff(second, e.createdate, ta.createdate) = 0

update t
set t.[service] = @elitename,
turbo = o.turbo,
ispromocouponapplied = o.IsPromoCouponApplied,
ispermanentpromocouponapplied = o.ispermanentpromocouponapplied,
specialpromo = o.IsCreatedWithPromoPrice,
FreeCommission = o.FreeCommission
from #tmp_al_final_transactions_table t
inner join [order] o on o.orderid = t.orderid
where REPLACE(t.transactiontype, '™', '') = @elitename
and t.[service] <> @elitename

update t
set t.[service] = case when prod.[name] = @proname and o.IsEliteTravelAdvantagePro = 1 then @elitename else prod.[name] end,
turbo = o.turbo,
ispromocouponapplied = o.IsPromoCouponApplied,
ispermanentpromocouponapplied = o.ispermanentpromocouponapplied,
specialpromo = o.IsCreatedWithPromoPrice,
FreeCommission = o.FreeCommission
from #tmp_al_final_transactions_table t
inner join [order] o on o.orderid = t.orderid
inner join [product] prod on prod.productid = o.productid
where t.transactiontype like '%Turbo%'
and o.turbo = 1

update t
set t.[service] = @elitename
from #tmp_al_final_transactions_table t
inner join [order] o on o.orderid = t.orderid
inner join [product] prod on prod.productid = o.productid
where t.[service] = @proname
and o.IsEliteTravelAdvantagePro = 1

update t
set t.couponused = o.CouponCode, t.coupontype = ct.[Description]
from #tmp_al_final_transactions_table t
inner join [order] o on o.orderid = t.orderid
left join Coupons c on c.CouponCode = o.couponcode
left join CouponsTypes ct on ct.CouponTypeID = c.CouponTypeID
where t.couponused is null

update t
set t.freecommission = 1
from #tmp_al_final_transactions_table t
inner join [order] o on o.orderid = t.orderid
inner join promoters p on p.promoterid = t.promoterid
where t.couponused like '%99'
and t.createdate >= p.enrolldate

IF OBJECT_ID('tempdb..#tmp_al_transactions_resume') IS NOT NULL DROP TABLE #tmp_al_transactions_resume;

;with refunds as (
	select distinct *
	from #tmp_al_final_transactions_table
	where amount < -100.00
),

candidate_transactions as (
	select distinct *
	from #tmp_al_final_transactions_table
	where transactiontype not in ('Token Purchase', 'Travel Credits', 'BizCenter Fee MWRLife')
	and (
		(
			amount > 200.00
			and (transactiontype is null or transactiontype like '%Enrollment Elite%' or [description] like '%to Elite%')
		)
		or
		(
			amount > 100.00
			and amount < 200.00
			and (transactiontype is null or transactiontype like '%Travel Advantage™ Elite%')
		)
	)
)

select t.*
into #tmp_al_transactions_resume
from candidate_transactions t
left join refunds r 
	on r.userid = t.userid 
	and r.orderid = t.orderid 
	and (r.amount + t.amount <= 0.00) 
	and t.createdate <= r.createdate 
	and dateadd(month, 1, t.createdate) >= r.createdate
where r.transactionid is null;

CREATE CLUSTERED INDEX IX_tmp_al_transactions_resume_user_order_date
ON #tmp_al_transactions_resume (userid, orderid, createdate);

CREATE NONCLUSTERED INDEX IX_tmp_al_transactions_resume_amount_type
ON #tmp_al_transactions_resume (amount, transactiontype)
INCLUDE (userid, orderid, createdate);

;with valid_enrollments as (
	select *
	from #tmp_al_transactions_resume
	where amount > 200.00
	and (transactiontype is null or transactiontype like '%Enrollment Elite%' or [description] like '%to Elite%')
),

valid_renewals as (
	select *
	from #tmp_al_transactions_resume
	where amount > 100.00
	and amount < 200.00
	and (transactiontype is null or transactiontype like '%Travel Advantage™ Elite%')
),

check_enrollments as (
	select distinct
		e.first_half_commission_id,
		e.first_half_fsb_no,
		e.is_standard_fsb,
		e.promo_window_start,
		e.promo_window_end,

		e.sponsoruserid,
		e.sponsorid,
		e.sponsorusername,
		e.sponsorname,
		e.sponsorenrolldate,
		e.EarnedDate as first_half_earneddate,

		e.UserId,
		e.CustomerID,
		e.promoterid,
		e.UserName,
		e.membername,
		e.orderid,
		e.orderstatus,
		e.servicename,
		ve.createdate as enrollmentdate,

		dateadd(day, 1, cast(cast(dateadd(day, 14, dateadd(month, 1, ve.createdate)) as date) as datetime)) as max_renewal_date,

		ve.transactiontype,
		ve.[description] as transactiondescription,
		ve.amount
	from #tmp_al_direct_enrollments_resume e
	inner join valid_enrollments ve
		on ve.userid = e.userid
		and isnull(ve.orderid, 0) = isnull(e.orderid, 0)
),

last_selection as (
	select
		ce.first_half_commission_id,
		ce.first_half_fsb_no,
		ce.is_standard_fsb,
		ce.promo_window_start,
		ce.promo_window_end,
		ce.first_half_earneddate,

		ce.sponsoruserid,
		ce.sponsorid,
		ce.sponsorusername,
		ce.sponsorname,
		ce.sponsorenrolldate,
		case isnull(p.agentstatus, 0)
			when 1 then 'Active'
			else 'Inactive'
		end as sponsorActive,
		case isnull(p.active, 0)
			when 0 then 'Unqualified'
			when 1 then 'Qualified'
			when 2 then 'Cancelled'
		end as sponsorQualified,

		ce.UserId,
		ce.CustomerID,
		ce.promoterid,
		ce.UserName,
		ce.membername,
		ce.orderid,
		ce.orderstatus,
		ce.servicename,
		ce.enrollmentdate,
		ce.max_renewal_date,
		ce.transactiontype,
		ce.transactiondescription,
		ce.amount,

		r.renewal_fee_date,
		r.renewal_fee_transactiontype,
		r.renewal_fee_transactiondescription,
		r.renewal_fee_amount
	from check_enrollments ce
	inner join Promoters p
		on p.PromoterId = ce.sponsorid
	outer apply (
		select top 1
			vr.createdate as renewal_fee_date,
			vr.transactiontype as renewal_fee_transactiontype,
			vr.[description] as renewal_fee_transactiondescription,
			vr.amount as renewal_fee_amount
		from valid_renewals vr
		where vr.userid = ce.userid
		  and isnull(vr.orderid, 0) = isnull(ce.orderid, 0)
		  and vr.createdate < ce.max_renewal_date
		order by vr.createdate
	) r
),

ordered_members as (
	select
		ls.*,
		row_number() over(
			partition by ls.first_half_commission_id, ls.sponsoruserid, ls.sponsorid
			order by ls.enrollmentdate asc, ls.userid asc, ls.orderid asc
		) as member_seq
	from last_selection ls
),

pair_members as (
	select
		om.*,

		case 
			when om.is_standard_fsb = 1 then ((om.member_seq - 1) / 2) + 1
			else om.first_half_fsb_no
		end as fsb_no,

		case 
			when om.is_standard_fsb = 1 then case when om.member_seq % 2 = 1 then 1 else 2 end
			else om.member_seq
		end as pair_pos

	from ordered_members om
	where 
		(
			om.is_standard_fsb = 1
			and om.member_seq <= 6
		)
		or
		(
			om.is_standard_fsb = 0
			and om.member_seq <= 2
		)
),

pair_resume as (
	select
		pm.first_half_commission_id,
		pm.first_half_fsb_no,
		pm.is_standard_fsb,
		pm.promo_window_start,
		pm.promo_window_end,

		pm.sponsoruserid,
		pm.sponsorid,
		pm.sponsorusername,
		pm.sponsorname,
		pm.sponsorenrolldate,
		pm.sponsorActive,
		pm.sponsorQualified,
		pm.fsb_no,

		count(*) as members_in_pair,
		sum(case when pm.renewal_fee_date is not null then 1 else 0 end) as renewed_members_in_pair,

		max(case when pm.pair_pos = 1 then pm.userid end) as member1_userid,
		max(case when pm.pair_pos = 1 then pm.username end) as member1_username,
		max(case when pm.pair_pos = 1 then pm.membername end) as member1_name,
		max(case when pm.pair_pos = 1 then pm.orderid end) as member1_orderid,
		max(case when pm.pair_pos = 1 then pm.servicename end) as member1_service,
		max(case when pm.pair_pos = 1 then pm.enrollmentdate end) as member1_enrollmentdate,
		max(case when pm.pair_pos = 1 then pm.renewal_fee_date end) as member1_renewal_fee_date,

		max(case when pm.pair_pos = 2 then pm.userid end) as member2_userid,
		max(case when pm.pair_pos = 2 then pm.username end) as member2_username,
		max(case when pm.pair_pos = 2 then pm.membername end) as member2_name,
		max(case when pm.pair_pos = 2 then pm.orderid end) as member2_orderid,
		max(case when pm.pair_pos = 2 then pm.servicename end) as member2_service,
		max(case when pm.pair_pos = 2 then pm.enrollmentdate end) as member2_enrollmentdate,
		max(case when pm.pair_pos = 2 then pm.renewal_fee_date end) as member2_renewal_fee_date
	from pair_members pm
	group by
	pm.first_half_commission_id,
	pm.first_half_fsb_no,
	pm.is_standard_fsb,
	pm.promo_window_start,
	pm.promo_window_end,
	pm.sponsoruserid,
	pm.sponsorid,
	pm.sponsorusername,
	pm.sponsorname,
	pm.sponsorenrolldate,
	pm.sponsorActive,
	pm.sponsorQualified,
	pm.fsb_no
),

pending_fsb as (
	select distinct
		tbp.id as first_half_commission_id,
		tbp.userid as sponsoruserid,
		tbp.promoterid as sponsorid,
		tbp.username as sponsorusername,
		tbp.membername as sponsorname,
		tbp.enrolldate as sponsorenrolldate,
		tbp.commissiontype,
		tbp.amount as first_half_amount,
		tbp.[description] as first_half_description,
		tbp.earneddate as first_half_earneddate,
		tbp.paymentdate as first_half_paymentdate,
		case
			when tbp.commissiontype like '%Fast Start Bonus 1%' then 1
			when tbp.commissiontype like '%Fast Start Bonus 2%' then 2
			when tbp.commissiontype like '%Fast Start Bonus 3%' then 3
		end as fsb_no
	from #tmp_al_fsb_to_be_paid tbp
	where tbp.commissiontype like '%Fast Start Bonus 1%'
	or tbp.commissiontype like '%Fast Start Bonus 2%'
	or tbp.commissiontype like '%Fast Start Bonus 3%'
),

final_resume_tobepaid as (
	select
		pf.first_half_commission_id,
		pf.sponsoruserid,
		pf.sponsorid,
		pr.sponsorusername,
		pr.sponsorname,
		pr.sponsorenrolldate,
		pr.sponsorActive,
		pr.sponsorQualified,

		pf.fsb_no,
		pf.commissiontype,
		pf.first_half_description,
		pf.first_half_earneddate,
		pf.first_half_paymentdate,
		pf.first_half_amount,
		pf.first_half_amount as second_half_amount_to_pay,

		pr.member1_userid,
		pr.member1_username,
		pr.member1_name,
		pr.member1_orderid,
		pr.member1_service,
		pr.member1_enrollmentdate,
		pr.member1_renewal_fee_date,

		pr.member2_userid,
		pr.member2_username,
		pr.member2_name,
		pr.member2_orderid,
		pr.member2_service,
		pr.member2_enrollmentdate,
		pr.member2_renewal_fee_date,
		pr.is_standard_fsb,
		pr.promo_window_start,
		pr.promo_window_end

	from pending_fsb pf
	inner join pair_resume pr
		on pr.first_half_commission_id = pf.first_half_commission_id
		and pr.sponsoruserid = pf.sponsoruserid
		and pr.sponsorid = pf.sponsorid
		and pr.fsb_no = pf.fsb_no
	where pr.members_in_pair = 2
	and pr.renewed_members_in_pair = 2
),

final_list as (
	select 
		p.first_half_commission_id,
		p.first_half_earneddate,
		concat('https://www.mwrlife.com/admin/paymentinfo/', p.sponsorusername) as paymentlink,
		p.sponsoruserid,
		p.sponsorusername,
		p.sponsorname,
		p.fsb_no,
		case fsb_no when 1 then @fsb1id when 2 then @fsb2id when 3 then @fsb3id else null end as fsb2ndhalfid,
		case fsb_no when 1 then @fsb1 when 2 then @fsb2 when 3 then @fsb3 else null end as fsb2ndhalf,
		p.second_half_amount_to_pay,
		'Second Half' as commissiondescription,

		d.renewal_based_earneddate,
		d.min_allowed_earneddate,

		case 
			when d.renewal_based_earneddate < d.min_allowed_earneddate then d.min_allowed_earneddate
			else d.renewal_based_earneddate
		end as earneddate,

		CASE ISNULL(pr.agentstatus, 0)
			WHEN 1 THEN 'Active'
			ELSE 'Inactive'
		END AS Active,

		CASE ISNULL(pr.active, 0)
			WHEN 0 THEN 'Unqualified'
			WHEN 1 THEN 'Qualified'
			WHEN 2 THEN 'Cancelled'
		END AS Qualified,
		p.is_standard_fsb,
		p.promo_window_start,
		p.promo_window_end
	from final_resume_tobepaid p
	inner join Promoters pr 
		on pr.UserProfileId = p.sponsoruserid
	cross apply (
		select 
			cast(
				case 
					when p.member1_renewal_fee_date > p.member2_renewal_fee_date 
						then p.member1_renewal_fee_date 
					else p.member2_renewal_fee_date 
				end 
			as date) as renewal_based_earneddate,

			cast(dateadd(day, 20, p.first_half_earneddate) as date) as min_allowed_earneddate
	) d
),

final_list_counted as (
	select
		f.*,
		count(*) over (
			partition by f.sponsoruserid, f.fsb_no
		) as same_bonus_count,
		row_number() over (
			partition by f.sponsoruserid, f.fsb_no
			order by f.earneddate, f.first_half_earneddate, f.first_half_commission_id
		) as same_bonus_seq
	from final_list f
),

more_than_once as (
	select
		f.sponsoruserid,
		f.sponsorusername,
		f.sponsorname,
		f.fsb_no,
		f.fsb2ndhalf,
		count(*) as qty
	from final_list f
	where f.Active = 'Active'
	group by
		f.sponsoruserid,
		f.sponsorusername,
		f.sponsorname,
		f.fsb_no,
		f.fsb2ndhalf
	having count(*) > 1
)
select

	f.sponsoruserid,
	f.sponsorname,
	f.sponsorusername,
	f.fsb2ndhalf,
	f.earneddate,
	convert(varchar, cast(f.earneddate as datetime), 101) as earneddatestr,
	cast(f.second_half_amount_to_pay as money) as second_half_amount_to_pay,
	f.commissiondescription,
	f.same_bonus_count,
	f.same_bonus_seq,
	case 
		when f.is_standard_fsb = 1 then 'Normal'
		else 'Promotion / Outside 21 days'
	end as fsb_rule,
	f.promo_window_start,
	f.promo_window_end
from final_list_counted f
where f.Active = 'Active'
and (@userid is null or @userid = f.sponsoruserid)
and not exists (
	select 1
	from DailyRealTimeCommission com
	inner join Promoters p 
		on p.promoterid = com.promoterid
	where p.userprofileid = f.sponsoruserid
	and com.CommissionTypeID = f.fsb2ndhalfid
	and cast(com.earneddate as date) >= dateadd(day, 30, cast(f.first_half_earneddate as date))
	and cast(com.earneddate as date) <= dateadd(day, 50, cast(f.first_half_earneddate as date))
	and cast(com.amount as money) = cast(f.second_half_amount_to_pay as money)
)
and not exists (
	select 1
	from more_than_once m
	where m.sponsoruserid = f.sponsoruserid
	  and m.fsb_no = f.fsb_no
)
and renewal_based_earneddate > dateadd(day, 25, first_half_earneddate)
--and renewal_based_earneddate >= '2025-01-01'
order by f.earneddate desc, f.fsb2ndhalf asc, f.second_half_amount_to_pay desc;

drop table if exists #tmp_al_fsb_paid_resume;
drop table if exists #tmp_al_fsb_to_be_paid;
drop table if exists #tmp_al_candidate_sponsors;
drop table if exists #tmp_al_direct_enrollments_resume;
drop table if exists #tmp_al_final_transactions_table;
drop table if exists #tmp_al_transactions_resume;