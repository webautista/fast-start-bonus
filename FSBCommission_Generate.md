# FSBCommission_Generate.sql

## Proposito

Generar cabeceras y detalles de comision FSB a partir de `dbo.FSBTrackings`, tanto para `FIRST` como para `SECOND`, respetando la regla de renewals validos.

## Parametros

- `@PromotionID`
- `@SponsorID = NULL`

## Flujo implementado

1. Abre transaccion y toma un `sp_getapplock` por promocion.
2. Calcula elegibilidad de `FIRST` usando conteo de promoters distintos por grupo:
   - `FSB1` normal con al menos 2 promoters.
   - `FSB1_EXT` puede otorgar cabecera `FSB1` si tiene al menos 2 y no existe `FSB1` normal.
   - `FSB2` exige `FSB1` normal previo y al menos 2 promoters en tracking `FSB2`.
   - `FSB3` exige `FSB2` elegible y al menos 2 promoters en tracking `FSB3`.
3. Inserta cabeceras `FIRST` en `dbo.FSBCommission` si no existen.
4. Inserta detalles `FIRST` en `dbo.FSBCommissionDetail`:
   - Para `FSB1`, usa filas `FSB1` normales o `FSB1_EXT` si la extension fue la que califico.
   - Para `FSB2` y `FSB3`, usa solo los trackings de su grupo.
5. Evalua renewals validos por tracking:
   - Revisa `FirstRPHID` y `SecondRPHID`.
   - Renewal valido = pago `SUCCESS` no revertido entre 1 y 44 dias desde `OrderDate`.
6. Cuenta renewals validos por grupo de `FIRST`.
7. Calcula elegibilidad de `SECOND`:
   - `FSB1 SECOND`: al menos 2 renewals validos del grupo FSB1.
   - `FSB2 SECOND`: al menos 2 renewals validos de FSB1 y al menos 2 de FSB2.
   - `FSB3 SECOND`: al menos 2 renewals validos de FSB1, FSB2 y FSB3.
8. Inserta cabeceras `SECOND` si no existen.
9. Inserta detalles `SECOND`:
   - Solo trackings que ya estaban en `FIRST`.
   - Solo promoters con renewal valido.
   - `FSB2 SECOND` arrastra renovados de `FSB1` y `FSB2`.
   - `FSB3 SECOND` arrastra renovados de `FSB1`, `FSB2` y `FSB3`.

## Reglas de negocio clave

- `FSB1_EXT` nunca se guarda como cabecera de comision; se transforma en `FSB1`.
- `FIRST` guarda todos los promoters validos del grupo.
- `SECOND` guarda solo promoters con renewal valido.
- La elegibilidad se basa en `COUNT(DISTINCT PromoterID)`.
- El procedimiento es idempotente gracias a `NOT EXISTS` con locks de actualizacion.

## Tablas y dependencias

- `dbo.FSBTrackings`
- `dbo.FSBCommission`
- `dbo.FSBCommissionDetail`
- `dbo.[Order]`
- `dbo.RecurringPaymentsHistory`

## Resultado esperado

Deja `dbo.FSBCommission` y `dbo.FSBCommissionDetail` sincronizadas con el tracking actual y con la politica de renewal de la promocion.
