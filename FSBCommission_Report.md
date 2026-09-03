# FSBCommission_Report.sql

## Proposito

Reporte de auditoria de comisiones ya materializadas. Muestra exactamente que filas de `dbo.FSBTrackings` fueron usadas en `dbo.FSBCommission` y `dbo.FSBCommissionDetail`, tanto para `FIRST` como para `SECOND`.

## Parametros

- `@SponsorID = NULL`

## Comportamiento

1. Resuelve la promocion FSB activa usando `GETDATE()`.
2. No ejecuta procesos de carga ni generacion; es un reporte de solo lectura.
3. Construye el reporte desde:
   - `dbo.FSBCommission`
   - `dbo.FSBCommissionDetail`
   - `dbo.FSBTrackings`
   - `dbo.[Order]`
   - `dbo.RecurringPaymentsHistory`
4. Recalcula renewal valido con la misma regla de 1 a 44 dias.
5. Devuelve una fila por detalle real de comision.

## Informacion que expone

- `CommissionFSBType`
- `HalfType`
- `TrackingFSBType`
- `PromoterID`
- `CustomerID`
- `ParticipantUserID`
- `CandidateType`
- `OrderID`
- fechas de ventanas FSB
- `FirstRPHID`
- `SecondRPHID`
- renewal valido y su fuente
- `AuditStatus`

## AuditStatus

Los estados principales son:

- `USED_FOR_FIRST_HALF`
- `USED_FOR_SECOND_HALF`
- `SECOND_HALF_DETAIL_WITHOUT_VALID_RENEWAL`

## Regla de renewal usada

Se considera renewal valido si:

- `FirstRPHID` o `SecondRPHID` existe
- el `CreateDate` esta entre 1 y 44 dias desde `OrderDate`

## Diferencia frente a TrackingReport

- Este reporte audita solo lo que ya llego a comision.
- No es una vista UI resumida.
- No colapsa `FIRST` y `SECOND` en una sola fila.
- No intenta mostrar candidatos `NO_FSB`, porque esos no generan comision.

## Cuando usarlo

- auditoria tecnica de comision
- revisiones de primera y segunda mitad
- analisis de renewals aplicados a pagos
