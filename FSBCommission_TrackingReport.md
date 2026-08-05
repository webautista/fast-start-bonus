# FSBCommission_TrackingReport.sql

## Proposito

Reporte operativo y de UI para revisar el estado del tracking FSB y su relacion con comisiones, renewals y ventanas proyectadas, en una sola vista por sponsor.

## Parametros

- `@SponsorID = NULL`
- `@ShowAllColumns = NULL`

## Comportamiento general

1. Resuelve la promocion FSB activa.
2. Si recibe `@SponsorID`, ejecuta antes:
   - `dbo.FSBTrackings_Load`
   - `dbo.FSBCommission_Generate`
3. Parte desde `dbo.FSBTrackings`.
4. Une informacion de `FIRST` y luego agrega `SECOND` sobre la misma fila.
5. Recalcula renewal valido con la regla de 1 a 44 dias.
6. Calcula columnas de estado para UI.
7. Limita la salida visual a `FSBDisplayRank <= 2` por grupo.

## Base de la fila

La fila base es una fila de `dbo.FSBTrackings`.

- Si existe comision `FIRST`, se presenta sobre esa fila.
- Si existe `SECOND`, no genera una fila nueva; se adjunta como columnas.
- Si no existe comision, la fila igual puede aparecer en tracking.

Esto permite mostrar:

- comisionados
- no comisionados
- `NO_FSB`

## Soporte actual de candidatos

El reporte ya soporta:

- `PROMOTER`
- `CUSTOMER`

Columnas relevantes:

- `CandidateType`
- `PromoterID`
- `CustomerID`
- `ParticipantUserID`
- `UserProfileID`

Para `CUSTOMER`, el fallback visible de `Ambassador` usa `CustomerID` y no el identificador sintetico negativo.

## Reglas visuales importantes

- Si `ProductID = 20` y `IsEliteTravelAdvantagePro = 1`, el producto mostrado es `Travel Advantage Elite`.
- `NO_FSB` se ordena despues de `FSB3`.
- Solo se muestran 2 filas por grupo visual para evitar duplicados y ruido en UI.

## Ventanas proyectadas

Si faltan fechas reales en tracking, el reporte proyecta ventanas solo para presentacion:

- `FSB1EndDate = FSB1Start + 7 dias`
- `FSB1ExtEndDate = FSB1Start + 14 dias`
- `FSB2StartDate = fin real de FSB1 o proyeccion`
- `FSB2EndDate = FSB2Start proyectado + 7 dias`
- `FSB3StartDate = fin real de FSB2 o proyeccion`
- `FSB3EndDate = FSB3Start proyectado + 7 dias`

Estas proyecciones no modifican `dbo.FSBTrackings`.

## Columnas de estado

El reporte calcula:

- `HasValidRenewal`
- `SecondHalfPaid`
- `SecondHalfGrantedCreateDate`
- `StatusColor`
- `StatusCode`
- `StatusText`

La regla de renewal sigue usando:

- `FirstRPHID`
- `SecondRPHID`
- `RecurringPaymentsHistory.CreateDate`
- ventana de 1 a 44 dias desde `OrderDate`

## Modos de salida

### `@ShowAllColumns = 1`

Devuelve vista tecnica completa:

- ids internos
- tipo de candidato
- ventanas reales/proyectadas
- RPHs
- datos de primera y segunda mitad
- columnas de estado

### `@ShowAllColumns IS NULL or 0`

Devuelve vista compacta para UI:

- sponsor
- FSB
- ambassador
- enroll/order date
- producto
- renewal
- estado

## Limites del reporte

- No es un validador completo.
- No muestra el universo total de `FSBCandidates`.
- Resume la vista a 2 filas por grupo visual.
- Esta orientado a seguimiento operativo, no a auditoria exhaustiva.
