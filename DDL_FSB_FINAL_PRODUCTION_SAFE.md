# DDL_FSB_FINAL_PRODUCTION_SAFE.sql

## Proposito

DDL final y no destructivo para instalar o actualizar FastStartBonus en una base existente, preservando historia y dejando la estructura alineada con el modelo actual de auditoria, tracking y comisiones.

## Objetos principales

1. `dbo.Promotions`
   - Tabla maestra de promociones.

2. `dbo.PromotionProducts`
   - Tabla de configuracion de productos por promocion.
   - Trabaja en modo exclusion por `IsExcluded = 1`.

3. `dbo.FSBCandidates`
   - Nuevo universo auditable completo a nivel orden.
   - Guarda candidatos `PROMOTER` y `CUSTOMER`.
   - Conserva estado de elegibilidad estatica y razon de descarte.

4. `dbo.FSBTrackings`
   - Tracking historico clasificado.
   - Soporta `FSB1`, `FSB1_EXT`, `FSB2`, `FSB3` y `NO_FSB`.
   - Incluye `CustomerID`, `ParticipantUserID` y `CandidateType`.

5. `dbo.FSBCommission`
   - Cabecera de comisiones.
   - Solo permite `FSB1`, `FSB2`, `FSB3`.

6. `dbo.FSBCommissionDetail`
   - Detalle por tracking usado en cada comision.

## Cambios funcionales clave

- Agrega `dbo.FSBCandidates` como tabla de auditoria del universo completo.
- Amplia `dbo.FSBTrackings` para soportar:
  - `CustomerID`
  - `ParticipantUserID`
  - `CandidateType`
  - `NO_FSB`
- Mantiene `FSB1_EXT` solo en tracking.
- Mantiene `FSBCommission` restringida a tipos comisionables.

## Logica de migracion incluida

- Si `dbo.PromotionProducts` no tiene `IsExcluded`, la agrega.
- Si `dbo.FSBTrackings` no tiene `CustomerID`, `ParticipantUserID` o `CandidateType`, los agrega.
- Reemplaza el `CHECK` de `FSBTrackings.FSBType` para incluir `NO_FSB`.
- Si hay filas viejas de `FSBTrackings` sin datos nuevos, intenta backfill de:
  - `CustomerID`
  - `ParticipantUserID`
  - `CandidateType = 'PROMOTER'`

## Restricciones y diseño

- `dbo.FSBCandidates.CandidateType` permite:
  - `PROMOTER`
  - `CUSTOMER`
- `dbo.FSBTrackings.CandidateType` permite:
  - `PROMOTER`
  - `CUSTOMER`
- `dbo.FSBTrackings.FSBType` permite:
  - `FSB1`
  - `FSB1_EXT`
  - `FSB2`
  - `FSB3`
  - `NO_FSB`
- `dbo.FSBCommission.FSBType` permite:
  - `FSB1`
  - `FSB2`
  - `FSB3`

## Indices relevantes

- `FSBCandidates`
  - `IX_FSBCandidates_Sponsor_Cycle_Type`
  - `IX_FSBCandidates_Order`
- `FSBTrackings`
  - indices para sponsor/ciclo/orden
  - indices para busquedas por `CandidateType`
  - soporte a joins con `FSBCommissionDetail`
- `FSBCommission` y `FSBCommissionDetail`
  - indices para headers/details por promocion, sponsor y tracking

## Reglas de negocio reflejadas

- El universo completo se audita antes de clasificar.
- `PromotionProducts` excluye productos; no define whitelist.
- `FSB1_EXT` puede existir en tracking, pero no como cabecera de comision.
- `NO_FSB` existe para auditoria y reporteria, no para pago.

## Cuando usarlo

- Instalacion desde cero.
- Actualizacion segura de un ambiente existente.
- Despliegue productivo donde no se puede perder historia.

## Orden relacionado

Despues de este DDL, los scripts que deben instalarse son:

1. `FSBTrackings_Load.sql`
2. `FSBCommission_Generate.sql`
3. `FSBCommission_Report.sql`
4. `FSBCommission_TrackingReport.sql`
