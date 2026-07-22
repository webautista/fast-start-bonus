# DDL_FSB_FINAL_PRODUCTION_SAFE.sql

## Proposito

DDL final, no destructivo y orientado a produccion para el modulo FSB. Preserva datos historicos y corrige la estructura para alinearla con la logica final de tracking y comisiones.

## Que implementa

1. `dbo.Promotions`
   - Crea la tabla si no existe.

2. `dbo.PromotionProducts`
   - Crea la tabla si no existe.
   - Si la tabla ya existe pero no tiene `IsExcluded`, agrega la columna.
   - Agrega FK hacia `dbo.Promotions`.

3. `dbo.FSBTrackings`
   - Crea la tabla historica de tracking si no existe.
   - Permite `FSB1`, `FSB1_EXT`, `FSB2`, `FSB3`.
   - Agrega FK hacia `dbo.Promotions`.

4. `dbo.FSBCommission`
   - Crea la tabla de cabeceras de comision si no existe.
   - Restringe `FSBType` a `FSB1`, `FSB2`, `FSB3`.
   - Si existia un `CHECK` viejo que permitia `FSB1_EXT`, lo reemplaza por la version final.
   - Agrega FK hacia `dbo.Promotions`.
   - Agrega FK opcional hacia `dbo.DailyRealTimeCommission` si esa tabla existe con columna `ID`.

5. `dbo.FSBCommissionDetail`
   - Crea la tabla de detalle si no existe.
   - Agrega FK hacia `dbo.FSBCommission`.
   - Agrega FK hacia `dbo.FSBTrackings`.

6. Indices internos FSB
   - Amplia el set de indices de `FSBTrackings`, `FSBCommission`, `FSBCommissionDetail` y `PromotionProducts`.
   - Agrega indices adicionales como `IX_FSBTrackings_Order`, `IX_FSBCommissionDetail_Tracking` e `IX_PromotionProducts_Excluded`.

7. Inserciones opcionales de configuracion
   - Deja comentado un bloque para crear una promo `FSB_TEST`.
   - Deja comentada la carga de productos excluidos `4` y `22`.

## Diferencias clave contra `DDL.sql`

- No usa `DROP TABLE`.
- Aplica o corrige restricciones sobre estructuras ya existentes.
- `FSBCommission` ya no permite `FSB1_EXT`.
- Agrega llaves foraneas reales.
- Define un set de indices mas completo.
- Incluye una pequena logica de migracion de estructura.

## Reglas de negocio reflejadas

- `FSB1_EXT` existe solo como clasificacion de tracking.
- Si la extension gana FSB1, la cabecera oficial de comision sigue siendo `FSB1`.
- `PromotionProducts` funciona en modo exclusion, no como lista blanca.

## Cuando usarlo

- Despliegues de produccion.
- Actualizacion segura de ambientes existentes.
- Base final para ambientes que ya contienen historia.
