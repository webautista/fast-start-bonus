# DDL.sql

## Proposito

Script base de esquema para la solucion FSB. Crea las tablas principales y un set inicial de indices para tracking y comisiones.

## Que implementa

1. `dbo.Promotions`
   - Catalogo de promociones.
   - Clave unica por `Code`.

2. `dbo.PromotionProducts`
   - Relacion entre promocion y producto.
   - Incluye `IsExcluded` para marcar productos que no deben contar.
   - En este script las llaves foraneas estan comentadas.

3. `dbo.FSBTrackings`
   - Tabla historica de tracking por sponsor, promoter, orden y ciclo FSB.
   - Guarda clasificaciones `FSB1`, `FSB1_EXT`, `FSB2`, `FSB3`.
   - Guarda `FirstRPHID` y `SecondRPHID`.
   - La clave unica evita duplicados por `PromotionID + SponsorID + PromoterID + OrderID + FSBType + SponsorFSB1Start`.

4. `dbo.FSBCommission`
   - Cabecera de comisiones FSB.
   - En esta version todavia permite `FSB1_EXT` en `FSBType`, lo que la vuelve una definicion previa a la version final de produccion.
   - Separa `HalfType` en `FIRST` y `SECOND`.

5. `dbo.FSBCommissionDetail`
   - Relacion entre una cabecera de comision y los trackings que la justifican.

6. Indices de soporte
   - `IX_FSBTrackings_Sponsor_Cycle_Type`
   - `IX_FSBTrackings_Promoter_Order`
   - `IX_FSBCommission_Sponsor_Cycle`
   - `IX_FSBCommissionDetail_Commission_Tracking`
   - `IX_PromotionProducts_Product_Promotion`

## Reglas importantes

- `FSBTrackings` si acepta `FSB1_EXT`.
- `FSBCommission` tambien acepta `FSB1_EXT` en este archivo, por eso no debe considerarse la definicion final de negocio.
- Hay un bloque comentado al inicio con `DROP TABLE`, util para entornos de prueba pero no para despliegue seguro.
- Las llaves foraneas existen solo como comentarios; no se aplican automaticamente.

## Cuando usarlo

- Bootstrap inicial de un ambiente local o de desarrollo.
- Referencia de estructura minima del modulo FSB.

## Limitaciones

- No es el DDL final de produccion.
- No migra restricciones existentes.
- No protege datos historicos si se decide activar manualmente el bloque de `DROP TABLE`.
