# FSBTrackings_Load.sql

## Proposito

Procedimiento principal de carga masiva para FastStartBonus. Construye el universo completo de candidatos, lo persiste en `dbo.FSBCandidates`, clasifica los candidatos en `dbo.FSBTrackings` y deja trazabilidad tanto para casos comisionables como para `NO_FSB`.

## Parametros

- `@PromotionID`
- `@SponsorID = NULL`

## Flujo implementado

1. Toma `sp_getapplock` antes de preparar datos sobre `FSB_Flow_<PromotionID>`: `Shared` con sponsor y `Exclusive` para la promocion completa; con sponsor tambien toma un lock `Exclusive` especifico del sponsor.
2. Valida que `@PromotionID` exista.
3. Construye `#ScopeSponsors` con sponsors que tienen ciclo FSB cargado.
4. Construye `#Universe` con el universo completo de ordenes:
   - `PROMOTER`: ordenes de promoters hijos del sponsor.
   - `CUSTOMER`: ordenes de customers asociados al sponsor por `SponsorMemberID`.
5. Construye `#BaseOrders` desde `#Universe` usando solo `IsStaticEligible = 1`.
6. Deduplica para clasificacion:
   - una orden por promoter
   - una orden por customer
7. Evalua ventanas dinamicas:
   - `FSB1`
   - `FSB1_EXT`
   - `FSB2`
   - `FSB3`
8. Inserta tambien `NO_FSB` para los candidatos elegibles que no entraron a un FSB valido.
9. Resuelve `FirstRPHID` y `SecondRPHID`.
10. Abre una transaccion corta para persistir candidatos y tracking:
    - persiste `#Universe` en `dbo.FSBCandidates` mediante `UPDATE + INSERT`
    - conserva `UPDLOCK, HOLDLOCK` solo para proteger el `NOT EXISTS` de candidatos
11. Refresca `dbo.FSBTrackings`:
    - elimina filas obsoletas en el scope
    - inserta filas nuevas
    - actualiza payload si cambio

12. Ejecuta automaticamente `dbo.FSBCommission_Generate` dentro de la misma transaccion, con el mismo `@PromotionID` y `@SponsorID`; el `COMMIT` ocurre despues de ambos procesos. Los reportes no ejecutan ninguno de estos procesos.

La transaccion corta comienza despues de construir la clasificacion y los renewals del loader. `FSBCommission_Generate` aun prepara sus propios calculos dentro de esa transaccion; separar tambien esa fase requiere un refactor adicional del generador.

## Universo de candidatos

La ventana del universo no se corta por `Promotions.StartDate/EndDate`.  
Se corta por ciclo del sponsor:

- desde `SponsorFSB1Start`
- hasta `SponsorFSB1Start + 21 dias`

Esto aplica tanto para `PROMOTER` como para `CUSTOMER`.

## Modelo de candidatos

### PROMOTER

- `CandidateType = 'PROMOTER'`
- `CandidateKey = PromoterID`
- `PromoterID = PromoterID`

### CUSTOMER

- `CandidateType = 'CUSTOMER'`
- `CandidateKey = -CustomerID`
- `PromoterID` queda sintetico en el flujo de clasificacion usando `CandidateKey`

La clave negativa permite mantener una sola logica de ventanas y conteos para promoters y customers, sin correr el proceso dos veces.

## Elegibilidad estatica auditada

`dbo.FSBCandidates` guarda tanto elegibles como no elegibles, con:

- `IsStaticEligible`
- `StaticEligibilityReason`
- `IsExcludedProduct`
- `IsCurrent`, `FirstSeenAt`, `LastSeenAt` e `InactivatedAt`

Ejemplos de descarte:

- promoter inactivo
- `FreeType`
- `SpecialCode`
- orden no `Active`
- producto excluido
- producto no permitido
- `FreeCommission`
- `IsDagCustomer`
- `IsCreatedWithPromoPrice`
- customer no elite
- promo coupon

## Reglas de clasificacion

- La clasificacion usa solo candidatos con `IsStaticEligible = 1`.
- Para `PROMOTER`, cuenta una sola orden por promoter.
- Para `CUSTOMER`, cuenta una sola orden por customer.
- `FSB1_EXT` existe solo como tracking.
- `FSB2` y `FSB3` siguen el modelo de ventanas dinamicas posterior al cierre real del grupo anterior.
- Si un candidato elegible no entra en `FSB1`, `FSB1_EXT`, `FSB2` o `FSB3`, se guarda como `NO_FSB`.

## Tablas afectadas

- lectura:
  - `dbo.Promotions`
  - `dbo.Promoters`
  - `dbo.UserProfile`
  - `dbo.MWRCustomers`
  - `dbo.[Order]`
  - `dbo.PromotionProducts`
  - `dbo.RecurringPaymentsHistory`
- escritura:
  - `dbo.FSBCandidates`
  - `dbo.FSBTrackings`

## Resultado esperado

Despues de correrlo:

- `dbo.FSBCandidates` contiene el universo completo auditado; las filas operativas vigentes se filtran con `IsCurrent = 1`
- Las filas que dejan de aparecer no se eliminan: quedan con `IsCurrent = 0` e `InactivatedAt` informado
- `dbo.FSBTrackings` contiene la clasificacion final
- existen filas `NO_FSB`
- `CustomerID`, `ParticipantUserID` y `CandidateType` quedan persistidos

## Validacion relacionada

El script complementario es `FSBTrackings_Load_validation.sql`.  
Debe ejecutarse despues de `dbo.FSBTrackings_Load`, no antes.
