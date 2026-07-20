# FSB Commission Report — Developer Field Guide

## 1. Purpose

`dbo.FSBCommission_Report` is the audit/reporting stored procedure for the Fast Start Bonus (FSB) commission engine.

It returns the commission records generated for the active FSB promotion, including:

- sponsor commission headers,
- promoters used to justify the commission,
- source order information,
- first and second payment references,
- valid renewal evaluation,
- the `RecurringPaymentsHistory.CreateDate` that justified a `SECOND` half payment.

This report is intended for commission audit, payout validation, dispute resolution, and developer integration.

---

## 2. Stored Procedure Signature

```sql
EXEC dbo.FSBCommission_Report
    @SponsorID = NULL;
```

### Parameter

| Parameter | Type | Required | Description |
|---|---:|---:|---|
| `@SponsorID` | `BIGINT` | No | Optional sponsor filter. When provided, the procedure refreshes FSB tracking and commission generation for that sponsor before returning the report. |

---

## 3. Active Promotion Resolution

The report does not receive `@PromotionID`.

Instead, it automatically resolves the active FSB promotion using:

```sql
SELECT TOP (1)
    @EffectivePromotionID = p.PromotionID
FROM dbo.Promotions p
WHERE p.Type = 'FSB'
  AND GETDATE() >= p.StartDate
  AND GETDATE() <= p.EndDate
ORDER BY
    p.StartDate DESC,
    p.PromotionID DESC;
```

If no active FSB promotion is found, the procedure raises:

```text
No active FSB promotion was found.
```

### Important

If more than one FSB promotion is active at the same time, the procedure uses the most recent one by:

```sql
StartDate DESC, PromotionID DESC
```

---

## 4. Auto Refresh Behavior

When `@SponsorID` is provided, the report refreshes the sponsor before returning results.

It executes:

```sql
EXEC dbo.FSBTrackings_Load
    @PromotionID = @EffectivePromotionID,
    @SponsorID = @SponsorID;

EXEC dbo.FSBCommission_Generate
    @PromotionID = @EffectivePromotionID,
    @SponsorID = @SponsorID;
```

### Behavior Summary

| Scenario | Behavior |
|---|---|
| `@SponsorID IS NULL` | Returns the report for the active promotion without triggering a mass refresh. |
| `@SponsorID IS NOT NULL` | Refreshes tracking and commission generation for that sponsor, then returns the report. |

This avoids accidental full-promotion recalculation when the report is executed without a sponsor filter.

---

## 5. Source Tables Used

The report reads from:

| Table | Purpose |
|---|---|
| `dbo.FSBCommission` | Commission header. Identifies sponsor, FSB type, half type, and cycle. |
| `dbo.FSBCommissionDetail` | Commission detail. Links each commission to the promoters that justified it. |
| `dbo.FSBTrackings` | Historical tracking table. Contains classified promoters, orders, FSB type, and RPH references. |
| `dbo.[Order]` | Source order table. Provides `OrderDate`. |
| `dbo.RecurringPaymentsHistory` | Payment history table. Provides `CreateDate` for renewal validation. |

---

## 6. Renewal Rule Used by the Report

A payment is considered a valid renewal if either `FirstRPHID` or `SecondRPHID` points to a successful, non-reverted `RecurringPaymentsHistory` record whose `CreateDate` is between **1 and 44 days** after the order date.

The report uses:

```sql
DATEDIFF(DAY, OrderDate, RecurringPaymentsHistory.CreateDate) BETWEEN 1 AND 44
```

### Important

The report uses:

```sql
RecurringPaymentsHistory.CreateDate
```

It does **not** use:

```sql
PaymentMade
```

---

## 7. Result Columns

## 7.1 Commission Header Fields

### `FSBCommissionID`

Unique identifier of the FSB commission header.

Source:

```sql
dbo.FSBCommission.FSBCommissionID
```

Used to identify the specific commission record.

---

### `PromotionID`

Promotion associated with the commission.

Source:

```sql
dbo.FSBCommission.PromotionID
```

The report only returns records for the active FSB promotion.

---

### `SponsorID`

Sponsor receiving the commission.

Source:

```sql
dbo.FSBCommission.SponsorID
```

When the procedure is executed with `@SponsorID`, this column should match the supplied sponsor.

---

### `SponsorFSB1Start`

Cycle key for the sponsor.

Source:

```sql
dbo.FSBCommission.SponsorFSB1Start
```

This identifies the specific FSB cycle for the sponsor.

The logical cycle identity is:

```text
PromotionID + SponsorID + SponsorFSB1Start
```

---

### `CommissionFSBType`

The FSB level of the commission header.

Source:

```sql
dbo.FSBCommission.FSBType
```

Valid values:

| Value | Meaning |
|---|---|
| `FSB1` | Fast Start Bonus level 1 |
| `FSB2` | Fast Start Bonus level 2 |
| `FSB3` | Fast Start Bonus level 3 |

Note: `FSB1_EXT` is not stored in `dbo.FSBCommission`. If FSB1 was achieved through extension, the commission header still uses `FSB1`.

---

### `HalfType`

Indicates whether the commission is for the first or second half.

Source:

```sql
dbo.FSBCommission.HalfType
```

Valid values:

| Value | Meaning |
|---|---|
| `FIRST` | First half commission |
| `SECOND` | Second half commission |

---

## 7.2 Tracking Detail Fields

### `FSBTrackingID`

Unique identifier of the tracking record used to justify the commission.

Source:

```sql
dbo.FSBTrackings.FSBTrackingID
```

This is the audit link between the commission and the promoter/order that contributed to it.

---

### `PromoterID`

Promoter used to justify the commission.

Source:

```sql
dbo.FSBTrackings.PromoterID
```

For `FIRST` half commissions, this can include all valid promoters in the FSB group, not just two.

For `SECOND` half commissions, this should include only promoters with a valid renewal.

---

### `OrderID`

Order associated with the promoter qualification.

Source:

```sql
dbo.FSBTrackings.OrderID
```

Joined to:

```sql
dbo.[Order].OrderID
```

---

### `OrderDate`

Order date used for FSB qualification and renewal calculation.

Source:

```sql
dbo.[Order].OrderDate
```

This is the anchor date for calculating renewal days.

---

### `TrackingFSBType`

FSB classification stored at the tracking level.

Source:

```sql
dbo.FSBTrackings.FSBType
```

Valid values:

| Value | Meaning |
|---|---|
| `FSB1` | Normal FSB1 tracking |
| `FSB1_EXT` | FSB1 extension tracking |
| `FSB2` | FSB2 tracking |
| `FSB3` | FSB3 tracking |

This may differ from `CommissionFSBType` when a promoter is tracked as `FSB1_EXT`, because the commission header still uses `FSB1`.

---

## 7.3 Sponsor Window Fields

These fields show the sponsor’s FSB windows captured historically in `FSBTrackings`.

### `SponsorFSB1End`

End date/time of the sponsor’s FSB1 normal window.

Source:

```sql
dbo.FSBTrackings.SponsorFSB1End
```

---

### `SponsorFSB1ExtEnd`

End date/time of the sponsor’s FSB1 extension window.

Source:

```sql
dbo.FSBTrackings.SponsorFSB1ExtEnd
```

---

### `SponsorFSB2Start`

Start date/time of the sponsor’s FSB2 window.

Source:

```sql
dbo.FSBTrackings.SponsorFSB2Start
```

---

### `SponsorFSB2End`

End date/time of the sponsor’s FSB2 window.

Source:

```sql
dbo.FSBTrackings.SponsorFSB2End
```

---

### `SponsorFSB3Start`

Start date/time of the sponsor’s FSB3 window.

Source:

```sql
dbo.FSBTrackings.SponsorFSB3Start
```

---

### `SponsorFSB3End`

End date/time of the sponsor’s FSB3 window.

Source:

```sql
dbo.FSBTrackings.SponsorFSB3End
```

---

## 7.4 Payment Reference Fields

### `FirstRPHID`

First successful, non-reverted payment associated with the order.

Source:

```sql
dbo.FSBTrackings.FirstRPHID
```

This ID points to:

```sql
dbo.RecurringPaymentsHistory.ID
```

Important: this field is populated by `dbo.FSBTrackings_Load`.

---

### `FirstRPHCreateDate`

`CreateDate` of the first payment referenced by `FirstRPHID`.

Source:

```sql
dbo.RecurringPaymentsHistory.CreateDate
```

Joined through:

```sql
dbo.FSBTrackings.FirstRPHID = dbo.RecurringPaymentsHistory.ID
```

---

### `FirstRPHDays`

Number of days between `OrderDate` and `FirstRPHCreateDate`.

Calculated as:

```sql
DATEDIFF(DAY, OrderDate, FirstRPHCreateDate)
```

Used to determine whether `FirstRPHID` qualifies as a valid renewal.

---

### `SecondRPHID`

Second successful, non-reverted payment associated with the order.

Source:

```sql
dbo.FSBTrackings.SecondRPHID
```

This ID points to:

```sql
dbo.RecurringPaymentsHistory.ID
```

Important: this field is populated by `dbo.FSBTrackings_Load`.

---

### `SecondRPHCreateDate`

`CreateDate` of the second payment referenced by `SecondRPHID`.

Source:

```sql
dbo.RecurringPaymentsHistory.CreateDate
```

Joined through:

```sql
dbo.FSBTrackings.SecondRPHID = dbo.RecurringPaymentsHistory.ID
```

---

### `SecondRPHDays`

Number of days between `OrderDate` and `SecondRPHCreateDate`.

Calculated as:

```sql
DATEDIFF(DAY, OrderDate, SecondRPHCreateDate)
```

Used to determine whether `SecondRPHID` qualifies as a valid renewal.

---

## 7.5 Renewal Evaluation Fields

### `ValidRenewalRPHID`

The payment ID that qualifies as the valid renewal.

Possible values:

| Value | Meaning |
|---|---|
| `FirstRPHID` | First payment qualifies as renewal |
| `SecondRPHID` | Second payment qualifies as renewal |
| `NULL` | No valid renewal found |

The procedure checks `FirstRPHID` first, then `SecondRPHID`.

Validation rule:

```sql
DATEDIFF(DAY, OrderDate, RPH.CreateDate) BETWEEN 1 AND 44
```

---

### `ValidRenewalCreateDate`

The `RecurringPaymentsHistory.CreateDate` that qualified as the renewal date.

This is the core audit date for renewal validation.

---

### `ValidRenewalSource`

Indicates which tracking payment field supplied the valid renewal.

Possible values:

| Value | Meaning |
|---|---|
| `FirstRPHID` | `FirstRPHID` qualified as renewal |
| `SecondRPHID` | `SecondRPHID` qualified as renewal |
| `NULL` | No valid renewal |

---

### `RenewalDaysFromOrderDate`

Number of days between `OrderDate` and the valid renewal `CreateDate`.

Calculated as:

```sql
DATEDIFF(DAY, OrderDate, ValidRenewalCreateDate)
```

Expected valid range:

```text
1 to 44
```

---

### `HasValidRenewal`

Boolean indicator.

| Value | Meaning |
|---:|---|
| `1` | A valid renewal exists |
| `0` | No valid renewal exists |

Derived from:

```sql
ValidRenewalRPHID IS NOT NULL
```

---

### `SecondHalfGrantedCreateDate`

For `SECOND` half rows, this is the `RecurringPaymentsHistory.CreateDate` that justified the second half payment.

Logic:

```sql
CASE
    WHEN HalfType = 'SECOND' THEN ValidRenewalCreateDate
    ELSE NULL
END
```

This is the most important audit field for second half payout verification.

---

## 7.6 Audit Status Field

### `AuditStatus`

Describes how the row was used.

Possible values:

| Value | Meaning |
|---|---|
| `USED_FOR_FIRST_HALF` | The promoter/order was used to justify a `FIRST` half commission. |
| `USED_FOR_SECOND_HALF` | The promoter/order was used to justify a `SECOND` half commission and has a valid renewal. |
| `SECOND_HALF_DETAIL_WITHOUT_VALID_RENEWAL` | A `SECOND` half detail exists, but no valid renewal was found. This should be treated as an audit exception. |
| `UNKNOWN` | Fallback status. Should generally not occur. |

---

## 8. How to Use the Report

### General active FSB promotion report

```sql
EXEC dbo.FSBCommission_Report;
```

This returns all commission details for the currently active FSB promotion.

It does not trigger full recalculation.

---

### Sponsor-specific report with auto refresh

```sql
EXEC dbo.FSBCommission_Report
    @SponsorID = 327259;
```

This refreshes tracking and commission generation for the sponsor before returning results.

---

## 9. Expected Behavior

## 9.1 FIRST Half Rows

For `HalfType = 'FIRST'`:

- `SecondHalfGrantedCreateDate` should be `NULL`.
- `AuditStatus` should be `USED_FOR_FIRST_HALF`.
- `ValidRenewalRPHID` may or may not be populated, depending on payment timing, but it is not required for `FIRST`.

---

## 9.2 SECOND Half Rows

For `HalfType = 'SECOND'`:

- `ValidRenewalRPHID` should not be `NULL`.
- `ValidRenewalCreateDate` should not be `NULL`.
- `SecondHalfGrantedCreateDate` should not be `NULL`.
- `RenewalDaysFromOrderDate` should be between `1` and `44`.
- `AuditStatus` should be `USED_FOR_SECOND_HALF`.

If `AuditStatus = SECOND_HALF_DETAIL_WITHOUT_VALID_RENEWAL`, investigate immediately.

---

## 10. Implementation Notes for Developers

1. Do not use `EnrollDate` for this report or any FSB qualification logic.
2. Do not use `PaymentMade` for renewal validation.
3. Renewal validation must use `RecurringPaymentsHistory.CreateDate`.
4. The valid renewal window is `1` to `44` days from `OrderDate`.
5. `FSB1_EXT` belongs in `FSBTrackings`, not in `FSBCommission`.
6. `SponsorFSB1Start` is the sponsor cycle key.
7. When `@SponsorID` is provided, the report intentionally refreshes that sponsor before returning results.
8. When `@SponsorID` is not provided, the report does not trigger a full recalculation.

---

## 11. QA Queries

### Check for invalid SECOND half details

This query should return zero rows:

```sql
SELECT *
FROM dbo.FSBCommission_Report_Output -- replace with temp/output table if materialized
WHERE HalfType = 'SECOND'
  AND AuditStatus = 'SECOND_HALF_DETAIL_WITHOUT_VALID_RENEWAL';
```

If running directly from the procedure, export or capture the result set and filter by:

```text
HalfType = SECOND
AuditStatus = SECOND_HALF_DETAIL_WITHOUT_VALID_RENEWAL
```

---

## 12. Summary

`dbo.FSBCommission_Report` is the final audit-facing report for the FSB module.

It explains:

- who received the commission,
- which FSB level was paid,
- which half was paid,
- which promoter/order justified it,
- which payment record was used,
- which `CreateDate` granted the second half,
- whether the renewal was valid.

The report is safe for operational audit and developer verification of FSB commission generation.
