# Developer Guide — `dbo.FSBCommission_TrackingReport`

## 1. Purpose

`dbo.FSBCommission_TrackingReport` is the UI-friendly tracking report for the Fast Start Bonus (FSB) module.

This stored procedure is intended for screens like the FSB tracking dashboard, where the UI needs one row per promoter/order used in the `FIRST` half commission, with the `SECOND` half information attached to that same row.

This avoids showing duplicate rows where `FIRST` and `SECOND` appear separately.

---

## 2. Stored Procedure Name

```sql
dbo.FSBCommission_TrackingReport
```

---

## 3. Signature

```sql
EXEC dbo.FSBCommission_TrackingReport
    @SponsorID = NULL,
    @ShowAllColumns = NULL;
```

Parameters:

| Parameter | Type | Required | Description |
|---|---:|---:|---|
| `@SponsorID` | `BIGINT` | No | Optional sponsor filter. When provided, the SP refreshes tracking and commission generation for that sponsor before returning the report. |
| `@ShowAllColumns` | `BIT` | No | Controls the output shape. `NULL` or `0` returns the compact UI result. `1` returns the full technical/debug result. |

---

## 4. Active Promotion Resolution

The SP does **not** receive `@PromotionID`.

It automatically resolves the current active FSB promotion using:

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

If no active FSB promotion exists, the SP raises:

```text
No active FSB promotion was found.
```

### Important

If more than one FSB promotion is active at the same time, the SP uses the most recent one by:

```sql
StartDate DESC, PromotionID DESC
```

---

## 5. Auto Refresh Behavior

When `@SponsorID` is provided, the SP refreshes the sponsor before returning the result.

It executes:

```sql
EXEC dbo.FSBTrackings_Load
    @PromotionID = @EffectivePromotionID,
    @SponsorID = @SponsorID;

EXEC dbo.FSBCommission_Generate
    @PromotionID = @EffectivePromotionID,
    @SponsorID = @SponsorID;
```

This means the UI can safely call the SP for a specific sponsor and receive updated data.

### Behavior Summary

| Call Type | Behavior |
|---|---|
| `@SponsorID IS NULL` | Returns data for the active FSB promotion without running a full refresh. |
| `@SponsorID IS NOT NULL` | Refreshes tracking and commissions for that sponsor, then returns data. |

This avoids accidental full-promotion recalculation from the UI.

---

## 6. Main Design Rule

The report uses `FIRST` commission records as the base.

Then it attaches `SECOND` half information to the same row.

Conceptually:

```text
FIRST commission detail row
    + matching SECOND commission detail if it exists
```

This prevents duplicated visual rows.

---

## 7. Why This SP Exists

`dbo.FSBCommission_Report` is the audit report. It can show `FIRST` and `SECOND` as separate commission rows.

`dbo.FSBCommission_TrackingReport` is the screen/reporting version. It returns a single row per promoter/order based on the `FIRST` half, with second half status attached.

Use this SP for UI screens.

---

## 8. Output Modes

## 8.1 Compact UI Output

This is the default.

Call:

```sql
EXEC dbo.FSBCommission_TrackingReport
    @SponsorID = 327259;
```

or:

```sql
EXEC dbo.FSBCommission_TrackingReport
    @SponsorID = 327259,
    @ShowAllColumns = 0;
```

This returns only the columns needed for the UI and decision-making.

---

## 8.2 Full Technical Output

Call:

```sql
EXEC dbo.FSBCommission_TrackingReport
    @SponsorID = 327259,
    @ShowAllColumns = 1;
```

This returns all technical columns useful for debugging, QA, and audit support.

---

# 9. Compact UI Output Columns

The compact result returns these columns:

```text
SponsorID
SponsorFSB1Start
FSB1StartDate
FSB1EndDate
FSB1ExtStartDate
FSB1ExtEndDate
FSB2StartDate
FSB2EndDate
FSB3StartDate
FSB3EndDate
FSB
Ambassador
EnrollDate
Product
LastPayment
StatusColor
StatusCode
StatusText
OrderID
TrackingFSBType
CommissionFSBType
HasValidRenewal
ValidRenewalRPHID
SecondHalfPaid
```

---

# 10. Compact Output Field Explanation

## `SponsorID`

The sponsor receiving the FSB commission.

Source:

```sql
dbo.FSBCommission.SponsorID
```

---

## `SponsorFSB1Start`

The logical FSB cycle key for the sponsor.

The cycle identity is:

```text
PromotionID + SponsorID + SponsorFSB1Start
```

Use this field to distinguish multiple FSB cycles for the same sponsor.

---

## `FSB1StartDate`

Start date/time of the sponsor's FSB1 normal window.

---

## `FSB1EndDate`

End date/time of the sponsor's FSB1 normal window.

---

## `FSB1ExtStartDate`

Start date/time of the sponsor's FSB1 extension period.

In the current implementation, this is derived from:

```sql
SponsorFSB1End
```

---

## `FSB1ExtEndDate`

End date/time of the sponsor's FSB1 extension period.

---

## `FSB2StartDate`

Start date/time of the sponsor's FSB2 window.

---

## `FSB2EndDate`

End date/time of the sponsor's FSB2 window.

---

## `FSB3StartDate`

Start date/time of the sponsor's FSB3 window.

---

## `FSB3EndDate`

End date/time of the sponsor's FSB3 window.

---

## `FSB`

The FSB type to display in the UI.

This comes from:

```sql
dbo.FSBTrackings.FSBType
```

Possible values:

| Value | Meaning |
|---|---|
| `FSB1` | Normal FSB1 qualification |
| `FSB1_EXT` | FSB1 extension qualification |
| `FSB2` | FSB2 qualification |
| `FSB3` | FSB3 qualification |

### Important

`FSB1_EXT` is displayed here when the tracking row is extension-based.

Financially, the commission header still uses:

```sql
CommissionFSBType = 'FSB1'
```

because FSB1 extension still pays as FSB1.

---

## `Ambassador`

Display name of the promoter/ambassador.

Calculated from:

```sql
UserProfile.FirstName + UserProfile.LastName
```

Fallback order:

```text
FirstName + LastName
UserName
PromoterID
```

---

## `EnrollDate`

For this screen, this field is mapped to the qualification order date:

```sql
QualificationOrderDate AS EnrollDate
```

### Important

Although the UI may label it as `EnrollDate`, the FSB engine uses:

```sql
OrderDate
```

not the promoter's actual enrollment date.

---

## `Product`

Product name associated with the qualifying order.

Source:

```sql
dbo.Product.[Name]
```

Fallback:

```sql
ProductID
```

---

## `LastPayment`

Most recent available payment create date between the first and second RPH references.

Logic:

```sql
CASE
    WHEN SecondRPHCreateDate IS NOT NULL THEN SecondRPHCreateDate
    ELSE FirstRPHCreateDate
END
```

---

## `StatusColor`

UI status color.

Possible values:

| Value | Meaning |
|---|---|
| `GREEN` | Second half was granted for this row. |
| `RED` | Second half was not granted for this row. |

---

## `StatusCode`

Numeric status indicator.

| Value | Meaning |
|---:|---|
| `1` | Second half was granted. |
| `0` | Second half was not granted. |

---

## `StatusText`

Detailed status explanation.

Possible values:

| Value | Meaning |
|---|---|
| `SECOND_HALF_GRANTED` | This promoter/order was used for first half and also has a second half detail. |
| `VALID_RENEWAL_BUT_SECOND_NOT_GRANTED` | This promoter has a valid renewal, but the full group did not qualify for second half. |
| `NO_VALID_RENEWAL` | This promoter does not have a valid renewal. |

### Example

A promoter may have a valid renewal, but second half may still not be granted if the accumulated FSB rule is not satisfied.

For example:

```text
FSB2 SECOND requires:
2 valid renewals from FSB1
+
2 valid renewals from FSB2
```

If the promoter has a renewal but the group does not satisfy the full accumulated rule, the row can show:

```text
VALID_RENEWAL_BUT_SECOND_NOT_GRANTED
```

---

## `OrderID`

The qualifying order ID.

Source:

```sql
dbo.FSBTrackings.OrderID
```

---

## `TrackingFSBType`

The actual FSB classification from tracking.

Source:

```sql
dbo.FSBTrackings.FSBType
```

Possible values:

```text
FSB1
FSB1_EXT
FSB2
FSB3
```

Use this to understand the real classification of the promoter/order.

---

## `CommissionFSBType`

The FSB type stored in the commission header.

Source:

```sql
dbo.FSBCommission.FSBType
```

Possible values:

```text
FSB1
FSB2
FSB3
```

### Important

`CommissionFSBType` will not be `FSB1_EXT`.

If tracking is `FSB1_EXT`, the commission type will still be:

```text
FSB1
```

---

## `HasValidRenewal`

Indicates whether the promoter/order has a valid renewal payment.

| Value | Meaning |
|---:|---|
| `1` | Valid renewal exists. |
| `0` | No valid renewal exists. |

---

## `ValidRenewalRPHID`

The `RecurringPaymentsHistory.ID` that qualifies as the valid renewal.

The SP checks both:

```sql
FirstRPHID
SecondRPHID
```

The first one that qualifies is returned.

---

## `SecondHalfPaid`

Indicates whether this specific row was included in a `SECOND` half commission detail.

| Value | Meaning |
|---:|---|
| `1` | This row has a matching SECOND half detail. |
| `0` | This row does not have a matching SECOND half detail. |

---

# 11. Renewal Logic

The SP determines whether a payment is a valid renewal using:

```sql
DATEDIFF(DAY, OrderDate, RecurringPaymentsHistory.CreateDate) BETWEEN 1 AND 44
```

The SP evaluates both:

```sql
FirstRPHID
SecondRPHID
```

It does not use:

```sql
PaymentMade
```

It uses:

```sql
RecurringPaymentsHistory.CreateDate
```

---

# 12. FSB1 Extension Handling

`FSB1_EXT` is visible in the compact UI result through:

```sql
FSB
TrackingFSBType
```

However, commission headers do not store `FSB1_EXT`.

Expected values when the row is an extension row:

```text
FSB = FSB1_EXT
TrackingFSBType = FSB1_EXT
CommissionFSBType = FSB1
```

This is intentional.

---

# 13. Recommended UI Mapping

| UI Column | SP Column |
|---|---|
| FSB | `FSB` |
| Ambassador | `Ambassador` |
| Enroll Date | `EnrollDate` |
| Product | `Product` |
| Last Payment | `LastPayment` |
| Status | `StatusColor` or `StatusCode` |
| Status Tooltip | `StatusText` |

---

# 14. Recommended Header Mapping

| UI Header Field | SP Column |
|---|---|
| FSB1 Date Range Start | `FSB1StartDate` |
| FSB1 Date Range End | `FSB1EndDate` |
| FSB1 Extended Start | `FSB1ExtStartDate` |
| FSB1 Extended End | `FSB1ExtEndDate` |
| FSB2 Date Range Start | `FSB2StartDate` |
| FSB2 Date Range End | `FSB2EndDate` |
| FSB3 Date Range Start | `FSB3StartDate` |
| FSB3 Date Range End | `FSB3EndDate` |

Since the date range columns repeat on each row, the UI can take them from the first row for the selected sponsor/cycle.

---

# 15. Example Calls

## 15.1 UI Summary for a Sponsor

```sql
EXEC dbo.FSBCommission_TrackingReport
    @SponsorID = 327259;
```

or:

```sql
EXEC dbo.FSBCommission_TrackingReport
    @SponsorID = 327259,
    @ShowAllColumns = 0;
```

---

## 15.2 Full Debug Output for a Sponsor

```sql
EXEC dbo.FSBCommission_TrackingReport
    @SponsorID = 327259,
    @ShowAllColumns = 1;
```

---

## 15.3 General Active Promotion Output

```sql
EXEC dbo.FSBCommission_TrackingReport;
```

This returns data for the active FSB promotion without running a full refresh.

---

# 16. Status Interpretation

## `SECOND_HALF_GRANTED`

The row was included in a generated `SECOND` half commission detail.

Use:

```text
StatusColor = GREEN
StatusCode = 1
```

---

## `VALID_RENEWAL_BUT_SECOND_NOT_GRANTED`

The promoter has a valid renewal, but the accumulated group rule was not satisfied.

Example:

```text
FSB3 promoter has renewal,
but FSB1 or FSB2 does not have the required 2 renewals.
```

Use:

```text
StatusColor = RED
StatusCode = 0
```

---

## `NO_VALID_RENEWAL`

The promoter/order does not have a valid payment renewal between day 1 and day 44.

Use:

```text
StatusColor = RED
StatusCode = 0
```

---

# 17. Notes for Frontend Developers

1. Use compact mode for the screen.
2. Use full mode only for debugging or admin tools.
3. Do not treat repeated `SponsorID` or `SponsorFSB1Start` as duplicates.
4. Each row represents a promoter/order used in `FIRST` half.
5. `SECOND` information is attached to the same row.
6. `FSB1_EXT` appears in `FSB` and `TrackingFSBType`, not in `CommissionFSBType`.
7. For date headers, read the FSB window fields from the first row.
8. Use `OrderID`, `TrackingFSBType`, `CommissionFSBType`, `HasValidRenewal`, `ValidRenewalRPHID`, and `SecondHalfPaid` for decision logic.

---

# 18. Summary

`dbo.FSBCommission_TrackingReport` is the UI-focused FSB tracking report.

It returns a single result set using the `FIRST` half commission details as the base and attaching `SECOND` half data into the same row.

Default mode returns only the columns needed by the screen and decision logic.

Full mode returns all technical columns for debugging and audit support.
