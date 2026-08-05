# FastStartBonus Installation Guide

Target audience: DBA  
Scope: clean installation / first-time deployment from this folder  
Workspace: `C:\Users\emman\OneDrive\Sagaracorp\MWRLife\FastStartBonus\final`

## 1. Important Notes

- Use only `DDL_FSB_FINAL_PRODUCTION_SAFE.sql` for installation.
- Do not run `DDL.sql` if `DDL_FSB_FINAL_PRODUCTION_SAFE.sql` was already used.
- `CREATE PROCEDURE` / `ALTER PROCEDURE` scripts only install code. They do not execute the FSB process.
- `FSBTrackings_Load_validation.sql` is validation only. It does not load data.
- Test/helper files such as `fsb_promotion_test_inserts_and_updated_sps.sql` are not part of the standard installation.

## 2. Installation Order From Zero

Run the following scripts in this exact order:

1. `DDL_FSB_FINAL_PRODUCTION_SAFE.sql`
2. `FSBTrackings_Load.sql`
3. `FSBCommission_Generate.sql`
4. `FSBCommission_Report.sql`
5. `FSBCommission_TrackingReport.sql`

## 3. What Each Script Installs

### 3.1 `DDL_FSB_FINAL_PRODUCTION_SAFE.sql`

Creates or adjusts the base database objects, including:

- `dbo.Promotions`
- `dbo.PromotionProducts`
- `dbo.FSBCandidates`
- `dbo.FSBTrackings`
- `dbo.FSBCommission`
- `dbo.FSBCommissionDetail`
- supporting constraints, foreign keys, and indexes

Key behavior installed by this DDL:

- `dbo.FSBCandidates` stores the full auditable candidate universe.
- `dbo.FSBTrackings` supports `FSB1`, `FSB1_EXT`, `FSB2`, `FSB3`, and `NO_FSB`.
- `dbo.FSBCommission` supports only valid commission types: `FSB1`, `FSB2`, `FSB3`.

### 3.2 `FSBTrackings_Load.sql`

Installs `dbo.FSBTrackings_Load`, which:

- loads the full candidate universe into `dbo.FSBCandidates`
- classifies candidates into `dbo.FSBTrackings`
- persists `NO_FSB` rows for audit and reporting

### 3.3 `FSBCommission_Generate.sql`

Installs `dbo.FSBCommission_Generate`, which:

- reads `dbo.FSBTrackings`
- creates commission headers/details only for `FSB1`, `FSB2`, and `FSB3`
- does not generate commissions for `NO_FSB`

### 3.4 `FSBCommission_Report.sql`

Installs `dbo.FSBCommission_Report`.

### 3.5 `FSBCommission_TrackingReport.sql`

Installs `dbo.FSBCommission_TrackingReport`.

## 4. Required Business Data Before First Load

Before the first operational run, confirm the following data exists:

- one row in `dbo.Promotions` for the target FSB promotion
- required rows in `dbo.PromotionProducts`

Current known example:

- promotion code: `FSB_2026_MAIN`
- excluded products are handled through `dbo.PromotionProducts.IsExcluded = 1`

If the promotion master data is missing, `dbo.FSBTrackings_Load` will not process anything useful.

## 5. First Operational Run After Installation

After the objects are installed and promotion data exists, run:

```sql
DECLARE @PromotionID BIGINT;

SELECT @PromotionID = PromotionID
FROM dbo.Promotions
WHERE Code = 'FSB_2026_MAIN';

EXEC dbo.FSBTrackings_Load @PromotionID = @PromotionID;
EXEC dbo.FSBCommission_Generate @PromotionID = @PromotionID;
```

Notes:

- `dbo.FSBTrackings_Load` must run before `dbo.FSBCommission_Generate`.
- `dbo.FSBCommission_Generate` should not be executed before tracking data is loaded.

## 6. Optional Post-Install Validation

For non-production validation or controlled verification, run:

```sql
DECLARE @PromotionID BIGINT;

SELECT @PromotionID = PromotionID
FROM dbo.Promotions
WHERE Code = 'FSB_2026_MAIN';

-- inside FSBTrackings_Load_validation.sql set:
-- SET @PromotionID = <value>;
```

Then execute:

1. `FSBTrackings_Load_validation.sql`

Expected result after a successful load:

- expected and actual universe summaries match
- expected and actual tracking summaries match
- no rows in:
  - `MISSING_CANDIDATE`
  - `EXTRA_CANDIDATE`
  - `MISSING_TRACKING`
  - `EXTRA_TRACKING`
  - `TRACKING_PAYLOAD_MISMATCH`

## 7. Not Part Of Base Installation

The following scripts/files are not required for a standard clean install:

- `DDL.sql`
- `FSBTrackings_Rebuild.sql`
- `fsb_promotion_test_inserts_and_updated_sps.sql`
- `test-cases..sql`
- report exports under `report\`
- legacy reference under `PRO\`

## 8. Final DBA Checklist

1. Run `DDL_FSB_FINAL_PRODUCTION_SAFE.sql`
2. Run `FSBTrackings_Load.sql`
3. Run `FSBCommission_Generate.sql`
4. Run `FSBCommission_Report.sql`
5. Run `FSBCommission_TrackingReport.sql`
6. Confirm promotion/config data exists
7. Execute `dbo.FSBTrackings_Load`
8. Execute `dbo.FSBCommission_Generate`
9. Optionally run `FSBTrackings_Load_validation.sql`
