# FSBCommission_Generate.sql

## Proposito

Generar cabeceras y detalles de comision FSB a partir de `dbo.FSBTrackings`, respetando la elegibilidad de primera mitad y la regla de renewals validos para segunda mitad.

## Parametros

- `@PromotionID`
- `@SponsorID = NULL`

## Flujo implementado

1. Si se ejecuta solo, abre su propia transaccion. Si lo llama `FSBTrackings_Load`, participa en la transaccion existente.
2. Toma `sp_getapplock` sobre `FSB_Flow_<PromotionID>`: `Shared` con sponsor y `Exclusive` para la promocion completa; con sponsor tambien toma un lock `Exclusive` especifico del sponsor.
3. Calcula grupos elegibles de `FIRST` usando `COUNT(DISTINCT ft.PromoterID)`.
4. Inserta cabeceras `FIRST` faltantes en `dbo.FSBCommission`.
5. Inserta detalles `FIRST` faltantes en `dbo.FSBCommissionDetail`.
6. Calcula renewals validos por tracking usando `FirstRPHID` y `SecondRPHID`, sin bloqueo de actualizacion sobre la lectura de `FSBTrackings`.
7. Cuenta renewals validos por grupo `FIRST`.
8. Calcula elegibilidad de `SECOND`.
9. Inserta cabeceras `SECOND` faltantes.
10. Inserta detalles `SECOND` faltantes.

## Regla de primera mitad

### FSB1

- Elegible si existen al menos 2 participantes distintos en tracking `FSB1`.

### FSB1 por extension

- Si no existe `FSB1` normal elegible, `FSB1_EXT` puede otorgar comision `FSB1`.
- `FSB1_EXT` nunca crea cabecera con tipo `FSB1_EXT`.

### FSB2

- Requiere `FSB1` normal elegible.
- Requiere al menos 2 participantes distintos en tracking `FSB2`.

### FSB3

- Requiere `FSB2` elegible.
- Requiere al menos 2 participantes distintos en tracking `FSB3`.

## Regla de renewal valido

Un renewal es valido si:

- el pago es `SUCCESS`
- no esta revertido
- su `CreateDate` esta entre 1 y 44 dias desde `OrderDate`

Importante:

- se usa `RecurringPaymentsHistory.CreateDate`
- no se usa `PaymentMade`

## Regla de segunda mitad

### FSB1 SECOND

- minimo 2 renewals validos del grupo `FSB1`

### FSB2 SECOND

- minimo 2 renewals validos del grupo `FSB1`
- minimo 2 renewals validos del grupo `FSB2`

### FSB3 SECOND

- minimo 2 renewals validos del grupo `FSB1`
- minimo 2 renewals validos del grupo `FSB2`
- minimo 2 renewals validos del grupo `FSB3`

## Detalles que inserta

### FIRST

- Guarda todos los trackings validos del grupo ganador.
- Si `FSB1` vino por extension, usa filas `FSB1_EXT` pero la cabecera oficial es `FSB1`.

### SECOND

- Guarda solo trackings con renewal valido.
- `FSB2 SECOND` puede incluir detalles renovados de `FSB1` y `FSB2`.
- `FSB3 SECOND` puede incluir detalles renovados de `FSB1`, `FSB2` y `FSB3`.

## Interaccion con customers

El procedimiento sigue contando `COUNT(DISTINCT ft.PromoterID)`.  
Para rows `CUSTOMER`, `FSBTrackings_Load` ya persistio una clave sintetica negativa en `PromoterID`, por lo que customers tambien participan en los conteos sin romper la logica existente.

## Que no hace

- No genera comisiones para `NO_FSB`.
- No crea cabeceras `FSB1_EXT`.
- No recalcula tracking; asume que `dbo.FSBTrackings` ya fue refrescada.
- La preparacion de renewals y elegibilidad sigue ocurriendo dentro de su transaccion cuando es llamado por `FSBTrackings_Load`.

## Dependencias

- `dbo.FSBTrackings`
- `dbo.FSBCommission`
- `dbo.FSBCommissionDetail`
- `dbo.[Order]`
- `dbo.RecurringPaymentsHistory`

## Resultado esperado

Deja `dbo.FSBCommission` y `dbo.FSBCommissionDetail` sincronizadas con la clasificacion actual de tracking y la politica vigente de renewals.
