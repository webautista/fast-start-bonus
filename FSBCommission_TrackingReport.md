# FSBCommission_TrackingReport.sql

## Proposito

Reporte de UI para mostrar el estado operativo del tracking y de las comisiones FSB en una sola vista amigable para pantalla.

## Parametros

- `@SponsorID = NULL`
- `@ShowAllColumns = NULL`

## Flujo implementado

1. Resuelve la promocion FSB activa usando `GETDATE()`.
2. Si recibe `@SponsorID`, refresca antes:
   - `dbo.FSBTrackings_Load`
   - `dbo.FSBCommission_Generate`
3. Construye filas base desde `dbo.FSBTrackings`:
   - Parte de todas las filas de tracking de la promocion.
   - Hace `LEFT JOIN` a `dbo.FSBCommissionDetail` y `dbo.FSBCommission`.
   - Conserva filas sin comision `FIRST`, pero si existe comision solo toma `HalfType = 'FIRST'`.
   - Une `dbo.[Order]`, `dbo.Promoters`, `dbo.UserProfile`, `dbo.Product`, `dbo.RecurringPaymentsHistory` y `dbo.RecurringPayments`.
4. Recalcula renewal valido con la misma regla de 1 a 44 dias.
5. Une la informacion de `SECOND` sobre la misma fila base de tracking.
6. Calcula columnas de UI:
   - Ambassador
   - UserName
   - Product
   - LastPaymentCreateDate
   - RenewalDate
   - `HasValidRenewal`
   - `SecondHalfPaid`
   - `StatusColor`, `StatusCode`, `StatusText`
7. Proyecta fechas de ventana cuando la fecha real viene `NULL`, solo para presentacion:
   - `FSB1EndDate = real o FSB1StartDate + 7 dias`
   - `FSB1ExtEndDate = real o FSB1StartDate + 14 dias`
   - `FSB2StartDate = real o FSB1EndDate real o FSB1StartDate + 7 dias`
   - `FSB2EndDate = real o FSB2StartDate proyectado + 7 dias`
   - `FSB3StartDate = real o FSB2EndDate real o FSB1StartDate + 14 dias`
   - `FSB3EndDate = real o FSB3StartDate proyectado + 7 dias`
8. Limita la presentacion a las primeras 2 filas por grupo visual FSB.
9. Devuelve salida detallada o compacta segun `@ShowAllColumns`.

## Idea central del reporte

- La fila base es la de `FSBTrackings`.
- Si existe `FIRST`, sus datos se muestran sobre esa fila base.
- La informacion de `SECOND` no se muestra como fila separada; se agrega como columnas.
- Esto evita duplicar renglones en la UI.
- Las fechas proyectadas no cambian `dbo.FSBTrackings`; solo se calculan en la salida del reporte.

## Reglas y decisiones de diseno

- `FSB1_EXT` se muestra como extension de FSB1.
- La pantalla solo enseña top 2 por grupo visual.
- `UserName` forma parte de la salida del reporte y se entrega como ultima columna.
- `ProductName` tiene una regla especial: si `ProductID = 20` y `IsEliteTravelAdvantagePro = 1`, se muestra `Travel Advantage Elite`.
- En la salida compacta, la columna `EnrollDate` se alimenta desde `OrderDate`.
- El color resume el estado operativo:
  - `GREEN`: renewal valido pagado.
  - `YELLOW`: sin renewal exitoso todavia, pero con proximo cobro futuro.
  - `RED`: cancelado, vencido o fuera de regla.

## Limitaciones importantes

- No es un reporte de auditoria completo.
- No muestra todas las ordenes extra de `FSB3`; recorta a 2 filas por grupo.
- Solo trabaja sobre la promocion FSB actualmente activa.

## Cuando usarlo

- Pantalla operativa.
- Seguimiento rapido por sponsor.
- Debug visual cuando `@ShowAllColumns = 1`.
