# FSBCommission_Report.sql

## Proposito

Reporte de auditoria de comisiones FSB. Muestra las filas reales usadas en `dbo.FSBCommission` y `dbo.FSBCommissionDetail`, separando `FIRST` y `SECOND`.

## Parametros

- `@SponsorID = NULL`

## Flujo implementado

1. Resuelve la promocion FSB activa con `GETDATE()`.
2. Si recibe `@SponsorID`, refresca antes:
   - `dbo.FSBTrackings_Load`
   - `dbo.FSBCommission_Generate`
3. Construye `ReportBase` desde:
   - `dbo.FSBCommission`
   - `dbo.FSBCommissionDetail`
   - `dbo.FSBTrackings`
   - `dbo.[Order]`
   - `dbo.RecurringPaymentsHistory`
4. Recalcula renewal valido:
   - Usa `FirstRPHID` o `SecondRPHID`.
   - Debe estar entre 1 y 44 dias desde `OrderDate`.
5. Devuelve una fila por detalle real de comision, con informacion de:
   - tipo de comision
   - half
   - tracking usado
   - fechas FSB
   - pagos recurrentes
   - renewal valido
   - estado de auditoria

## Que audita exactamente

- Que filas entraron en `FIRST`.
- Que filas entraron en `SECOND`.
- Si la fila de `SECOND` tiene un renewal valido segun la regla vigente.
- Si un tracking fue usado para primera mitad o segunda mitad.

## Columnas de lectura clave

- `CommissionFSBType`
- `HalfType`
- `TrackingFSBType`
- `ValidRenewalRPHID`
- `ValidRenewalCreateDate`
- `RenewalDaysFromOrderDate`
- `HasValidRenewal`
- `SecondHalfGrantedCreateDate`
- `AuditStatus`

## Diferencia frente a `FSBCommission_TrackingReport.sql`

- Este si es un reporte de auditoria de comisiones.
- No colapsa `FIRST` y `SECOND` en una sola fila.
- No intenta ser una vista de UI con colores o resumen visual.

## Limite funcional

Aunque es el reporte correcto para auditar comisiones, sigue auditando solo lo que ya llego a `dbo.FSBCommission` y `dbo.FSBCommissionDetail`. No reemplaza la validacion completa de tracking sobre `dbo.FSBTrackings`.
