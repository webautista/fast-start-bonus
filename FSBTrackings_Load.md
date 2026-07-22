# FSBTrackings_Load.sql

## Proposito

Procedimiento incremental que recalcula y refresca `dbo.FSBTrackings` para una promocion FSB y, opcionalmente, para un sponsor especifico.

## Parametros

- `@PromotionID`
- `@SponsorID = NULL`

## Flujo implementado

1. Abre transaccion y toma un `sp_getapplock` por promocion.
2. Resuelve fechas de la promocion activa desde `dbo.Promotions`.
3. Construye `#ScopeSponsors` con sponsors que tienen ciclo FSB1 vigente en datos del sponsor.
4. Construye `#BaseOrders`:
   - Solo ordenes `Active`.
   - Solo productos no excluidos en `dbo.PromotionProducts`.
   - Solo una orden valida por promoter dentro del ciclo: la primera por `(OrderDate, OrderID)`.
5. Evalua `FSB1` normal:
   - Ventana inicial de 7 dias desde `SponsorFSB1Start`.
   - Si existe segunda orden, el fin real de FSB1 queda fijado en esa segunda orden.
6. Evalua `FSB1_EXT`:
   - Solo si FSB1 normal no completo.
   - Usa extension hasta dia 14.
   - Puede guardar filas aun cuando no existan 2 ordenes.
   - No desbloquea `FSB2` ni `FSB3`.
7. Evalua `FSB2`:
   - Empieza justo despues de la segunda orden de FSB1 normal.
   - Usa cursor determinista `(OrderDate, OrderID)`.
   - Excluye promoters ya usados en FSB1 o FSB1_EXT.
8. Evalua `FSB3`:
   - Empieza justo despues de la segunda orden de FSB2.
   - Excluye promoters ya usados en FSB1, FSB1_EXT y FSB2.
   - Como no existe FSB4, conserva todas las ordenes validas que entren en la ventana FSB3.
9. Unifica todo en `#Classified`.
10. Resuelve pagos por orden:
   - `FirstRPHID` = primer `SUCCESS` por `CreateDate`.
   - `SecondRPHID` = segundo `SUCCESS` por `CreateDate`.
11. Refresca `dbo.FSBTrackings`:
   - Borra filas obsoletas en el scope actual.
   - Inserta nuevas filas.
   - Actualiza fechas de ventana y RPHs cuando cambiaron.

## Reglas de negocio clave

- No registra todas las ordenes del sponsor; registra ordenes de promoters hijos del sponsor.
- No toma la compra propia del sponsor.
- Usa una sola orden por promoter por ciclo.
- Mantiene ventanas parciales para seguimiento, aunque no generen comision todavia.
- `FSB1_EXT` existe solo para tracking.
- `FSB3` puede terminar con mas de 2 filas si hay mas ordenes validas dentro de su ventana.

## Tablas y dependencias

- `dbo.Promotions`
- `dbo.Promoters`
- `dbo.UserProfile`
- `dbo.MWRCustomers`
- `dbo.[Order]`
- `dbo.PromotionProducts`
- `dbo.RecurringPaymentsHistory`
- `dbo.FSBTrackings`

## Resultado esperado

Deja `dbo.FSBTrackings` alineada con la clasificacion dinamica actual del sponsor y de la promocion, en forma idempotente para el scope ejecutado.
