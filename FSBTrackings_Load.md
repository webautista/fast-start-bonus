# FSBTrackings_Load.sql

## Proposito

Procedimiento principal de carga masiva para FastStartBonus. Construye el universo completo de candidatos, lo persiste en `dbo.FSBCandidates`, clasifica los candidatos en `dbo.FSBTrackings` y deja trazabilidad tanto para casos comisionables como para `NO_FSB`.

## Parametros

- `@PromotionID`
- `@SponsorID = NULL`

## Flujo implementado

1. Abre transaccion y toma `sp_getapplock` por promocion.
2. Valida que `@PromotionID` exista.
3. Construye `#ScopeSponsors` con sponsors que tienen ciclo FSB cargado.
4. Construye `#Universe` con el universo completo de ordenes:
   - `PROMOTER`: ordenes de promoters hijos del sponsor.
   - `CUSTOMER`: ordenes de customers asociados al sponsor por `SponsorMemberID`.
5. Persiste `#Universe` en `dbo.FSBCandidates`.
6. Construye `#BaseOrders` desde `dbo.FSBCandidates` usando solo `IsStaticEligible = 1`.
7. Deduplica para clasificacion:
   - una orden por promoter
   - una orden por customer
8. Evalua ventanas dinamicas:
   - `FSB1`
   - `FSB1_EXT`
   - `FSB2`
   - `FSB3`
9. Inserta tambien `NO_FSB` para los candidatos elegibles que no entraron a un FSB valido.
10. Resuelve `FirstRPHID` y `SecondRPHID`.
11. Refresca `dbo.FSBTrackings`:
   - elimina filas obsoletas en el scope
   - inserta filas nuevas
   - actualiza payload si cambio

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

- `dbo.FSBCandidates` contiene el universo completo auditado
- `dbo.FSBTrackings` contiene la clasificacion final
- existen filas `NO_FSB`
- `CustomerID`, `ParticipantUserID` y `CandidateType` quedan persistidos

## Validacion relacionada

El script complementario es `FSBTrackings_Load_validation.sql`.  
Debe ejecutarse despues de `dbo.FSBTrackings_Load`, no antes.
