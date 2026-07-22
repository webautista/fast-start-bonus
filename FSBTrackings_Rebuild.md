# FSBTrackings_Rebuild.sql

## Proposito

Procedimiento de reconstruccion completa de `dbo.FSBTrackings`. Borra el contenido actual y lo vuelve a cargar usando una logica mas simple y estatica basada en las fechas FSB ya guardadas en `dbo.Promoters`.

## Que hace

1. Abre transaccion.
2. Ejecuta `DELETE FROM dbo.FSBTrackings`.
3. Construye una base de ordenes sponsor-promoter desde:
   - `dbo.Promoters`
   - `dbo.UserProfile`
   - `dbo.MWRCustomers`
   - `dbo.[Order]`
4. Excluye productos `4` y `22` en forma fija.
5. Clasifica cada orden por ventanas estaticas:
   - `FSB1`
   - `FSB1_EXT`
   - `FSB2`
   - `FSB3`
6. Busca pagos:
   - `FirstRPHID` = primer `SUCCESS`.
   - `SecondRPHID` = primer `SUCCESS` que cae entre 30 y 44 dias desde `OrderDate`.
7. Inserta el resultado en `dbo.FSBTrackings`.

## Diferencias frente a `FSBTrackings_Load.sql`

- Este rebuild es total; `FSBTrackings_Load` es incremental por promocion y sponsor.
- Aqui la clasificacion usa fechas FSB estaticas del sponsor.
- No implementa ventanas dinamicas basadas en la segunda orden.
- Los productos excluidos estan hardcodeados como `4` y `22`.
- El criterio de `SecondRPHID` es distinto al loader actual.

## Interpretacion recomendada

Este procedimiento parece una pieza legacy o de backfill inicial. Sirve para reconstruir rapidamente una historia completa, pero no refleja la logica final dinamica usada por el pipeline actual.

## Riesgo operativo

- Es destructivo para `dbo.FSBTrackings`.
- Si se ejecuta despues de adoptar ventanas dinamicas, puede dejar datos inconsistentes respecto a `FSBTrackings_Load.sql`.

## Cuando usarlo

- Solo en mantenimiento controlado.
- Solo si se acepta rehacer por completo el tracking con esta logica simplificada.
