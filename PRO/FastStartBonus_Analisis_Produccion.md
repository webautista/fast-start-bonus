# Analisis detallado de `dbo.FastStartBonus` en produccion

Archivo analizado: `PRO/FastStartBonus.sql`  
Base objetivo del script: `mwrlifelive`  
Fecha del analisis: `2026-07-28`

## 1. Objetivo real del stored procedure

`dbo.FastStartBonus` es el SP legacy que hoy inserta comisiones de **primera mitad** de Fast Start Bonus directamente en `dbo.DailyRealTimeCommission`.

No usa el pipeline nuevo de `FSBTrackings` + `FSBCommission`.  
No genera headers/details desacoplados.  
No calcula segunda mitad.  
No hace reversos.  
Su responsabilidad real es:

1. Evaluar si el `@promoterid` califica para `FSB1`, `FSB2` y `FSB3` de **First Half**.
2. Insertar en `dbo.DailyRealTimeCommission` los tipos `105`, `107` y `109`.
3. Actualizar fechas del sponsor evaluado en `dbo.Promoters` (`FSB2StartDate` y `FSB3StartDate`).
4. Repetir casi la misma logica para el sponsor directo del promoter recibido.

En una sola ejecucion, el SP puede intentar comisionar:

- al promoter recibido en `@promoterid`
- y al sponsor directo de ese promoter

No sube mas de un nivel en la cadena.

## 2. Alcance exacto de la entrada

Parametro:

- `@promoterid int`

Interpretacion real del parametro:

- El promoter pasado es tratado como **sponsor a evaluar** en el primer bloque.
- Luego el SP obtiene su `SponsorId` y evalua a ese sponsor en un segundo bloque espejo.

## 3. Tablas base leidas

El SP lee estas tablas:

- `dbo.Promoters`
- `dbo.UserProfile`
- `dbo.MWRAutoStates`
- `dbo.MWRCustomers`
- `dbo.[Order]`
- `dbo.PromotersLevel`
- `dbo.CommissionsAmounts`
- `dbo.DailyRealTimeCommission`
- `dbo.RecurringPayments`

## 4. Tablas modificadas

### 4.1 Inserciones

Inserta en `dbo.DailyRealTimeCommission`:

- `CommissionTypeID = 105` para `FSB1 First Half`
- `CommissionTypeID = 107` para `FSB2 First Half`
- `CommissionTypeID = 109` para `FSB3 First Half`

Campos fijos relevantes en todos los inserts:

- `EarnedDate = GETDATE()`
- `PaymentDate = GETDATE() + 4`
- `Paid = 0`
- `[Type] = 0`
- `ReversalTransactionID = 0`
- `AgentID = 0`
- `CustomerID = 0`
- `Creation = GETDATE()`
- `OriginalAgentID = 0`
- `OrderID = 0`
- `CheckMatchOverTransactionID = NEWID()`

Descripcion insertada:

- normalmente `'First Half'`
- en el bloque extendido del sponsor se usa `'First Half!'`

### 4.2 Updates

Actualiza `dbo.Promoters`:

- al otorgar `FSB1` normal: `FSB2StartDate = GETDATE()`
- al otorgar `FSB2`: `FSB3StartDate = GETDATE()`
- al otorgar `FSB1` por extension de 14 dias:
  - `FSB2StartDate = GETDATE() - 90`
  - `FSB3StartDate = GETDATE() - 90`

No actualiza `FSB1EndDate`, `FSB2EndDate` ni `FSB3EndDate`.

## 5. Variables y tablas temporales internas

### 5.1 Variables de control principales

- `@sponsorID`
- `@applicationName`
- `@userid`
- `@enrolldate`
- `@FSB1StartDate`, `@FSB1EndDate`
- `@FSB2StartDate`, `@FSB2EndDate`
- `@FSB3StartDate`, `@FSB3EndDate`
- `@fsb1Amount`, `@fsb2Amount`, `@fsb3Amount`
- `@fsb1AmountExtended`
- `@EliteLevel1`, `@EliteLevel2`, `@EliteLevel3`, `@EliteLevelExtended`

### 5.2 Table variables

- `@VIPCountryList`
- `@promoter`
- `@promoterExtended`
- `@promoterfsb2`
- `@promoterfsb3`
- `@ExternalOrders`

### 5.3 Variables declaradas pero no usadas funcionalmente

Estas variables se calculan o declaran, pero no afectan ninguna decision final:

- `@QtyPlusFSB1`, `@QtyPlusFSB2`, `@QtyPlusFSB3`
- `@QtyProFSB1`, `@QtyProFSB2`, `@QtyProFSB3`
- `@QtyEliteFSB1`, `@QtyEliteFSB2`, `@QtyEliteFSB3`
- `@LowestRank1`, `@LowestRank2`, `@LowestRank3`
- `@EliteLevel`
- `@Sponsored`
- `@IsPermanentPromoCouponApplied`
- `@FreeCommission`

Ademas, `@ExternalOrders` se llena y se limpia, pero nunca participa en la logica final.

## 6. Flujo general del SP

El SP tiene dos bloques casi identicos:

1. Bloque A: evalua al promoter recibido en `@promoterid`.
2. Bloque B: borra temporales, recarga contexto y evalua al sponsor directo de ese promoter.

La secuencia logica de ambos bloques es:

1. Cargar fechas FSB, enrollment y usuario del sponsor evaluado.
2. Cargar candidatos de `FSB1`, `FSB1_EXT`, `FSB2`, `FSB3`.
3. Calcular cantidad de ordenes elite externas dentro de cada ventana.
4. Definir el monto `Elite` o `Mixed` para cada tramo.
5. Aplicar una regla historica especial de extension para enrollments entre agosto y octubre de 2021.
6. Intentar insertar `FSB1` first half.
7. Intentar insertar `FSB1` por extension de 14 dias.
8. Intentar insertar `FSB2` first half.
9. Intentar insertar `FSB3` first half.

## 7. Bloque A: detalle del promoter recibido

Referencia: aprox. lineas `45-328` de `PRO/FastStartBonus.sql`.

### 7.1 Carga de contexto

El SP busca en `dbo.Promoters` y `dbo.UserProfile`:

- `SponsorId` del promoter recibido
- `ApplicationName`
- `EnrollDate`
- `UserId`
- todas las fechas FSB (`FSB1/2/3 StartDate` y `EndDate`)

Esto convierte al `@promoterid` en el sponsor que se evaluara en el primer bloque.

### 7.2 Paises VIP

Carga en `@VIPCountryList` los paises de `dbo.MWRAutoStates` donde `VIPTrigger = 1`.

Sin embargo, esa lista solo se usa para calcular `@LowestRank1/2/3`, y esos valores luego no participan en ninguna decision.

### 7.3 Universo de ordenes externas

Llena `@ExternalOrders` con ordenes de clientes patrocinados por el sponsor evaluado:

- `Status = 'Active'`
- `OrderDate >= @FSB1StartDate`
- `OrderDate < @FSB1EndDate`
- excluye `ProductID` `22`, `19`, `4`
- `FreeCommission = 0`
- no DAG
- `IsCreatedWithPromoPrice = 0`

Observacion clave:

- `@ExternalOrders` no vuelve a usarse. Es codigo muerto a nivel funcional.

### 7.4 Construccion de candidatos por tramo

#### `@promoter` = candidatos FSB1

Se guardan los primeros `TOP 2` promoters del sponsor evaluado:

- `p.SponsorId = @promoterid`
- `EnrollDate between @FSB1StartDate and @FSB1EndDate`
- `FreeType = 0` o `NULL`
- `u.SpecialCode is null`
- con orden activa de producto `20,23,25,26,27,28`
- no DAG
- `FreeCommission = 0`
- `IsCreatedWithPromoPrice = 0`
- ordenados por `EnrollDate asc`

#### `@promoterExtended` = candidatos FSB1 extendido

Misma logica, pero la ventana es:

- `EnrollDate between @FSB1StartDate and DATEADD(day, 14, @FSB1StartDate)`

#### `@promoterfsb2` = candidatos FSB2

Misma logica general:

- ventana `@FSB2StartDate .. @FSB2EndDate`
- excluye promoters ya tomados en `@promoter`
- `TOP 2`

#### `@promoterfsb3` = candidatos FSB3

Misma logica general:

- ventana `@FSB3StartDate .. @FSB3EndDate`
- excluye promoters ya usados en `@promoter`
- excluye promoters ya usados en `@promoterfsb2`
- `TOP 2`

### 7.5 Conteos Elite externos

El SP arma cuatro conteos:

- `@EliteLevel1`
- `@EliteLevelExtended`
- `@EliteLevel2`
- `@EliteLevel3`

La idea real es sumar:

- promoters patrocinados con orden valida
- mas ordenes externas elite de clientes

Esto genera una unidad de evaluacion combinada que luego se compara contra `2`.

Importante:

- `@EliteLevel1` usa clientes externos del sponsor evaluado y exige `ProductID = 20`, `IsEliteTravelAdvantagePro = 1`, `Status = 'Active'`, `FreeCommission = 0`, no DAG y `IsCreatedWithPromoPrice = 0`.
- En ese conteo aparece dos veces `o.IsPromoCouponApplied = 0`.
- No se valida `IsPermanentPromoCouponApplied = 0` en ese primer conteo del bloque A.

### 7.6 Determinacion del monto Elite vs Mixed

Para cada tramo, el monto se define asi:

- si `conteo elite efectivo >= 2`, usa `CommissionsAmounts.CommissionID = 'FastStartBonusElite'`
- si no, usa `CommissionsAmounts.CommissionID = 'FastStartBonusMixed'`

La formula aplicada es:

- `count(promoters nivel 3 sin promo/permanent promo) + eliteCount >= 2` => `Elite`
- en cualquier otro caso => `Mixed`

Tramos calculados:

- `@fsb1Amount`
- `@fsb1AmountExtended`
- `@fsb2Amount`
- `@fsb3Amount`

## 8. Comportamiento exacto de FSB1 First Half

Referencia principal: aprox. lineas `247-290`.

### 8.1 Ruta regular de FSB1 (`CommissionTypeID = 105`)

El insert de `105` se intenta si:

1. `@fsb1Amount > 0`
2. y se cumple una de estas dos ramas:

Rama 1:

- `@EliteLevel1 + count(promoters activos en @promoter dentro de la ventana FSB1) = 2`
- y no existe ningun `DailyRealTimeCommission` `105` con `Creation >= @FSB1StartDate`

Rama 2:

- ya existe exactamente `1` registro `105` desde `@FSB1StartDate`
- y existen exactamente `2` registros en una consulta a `Promoters + UserProfile + MWRCustomers + Order + RecurringPayments`
- esa consulta exige:
  - `productID != 4`
  - `productID != 22`
  - `productID != 19`
  - `FreeCommission = 0`
  - `r.paymentcount = 2`
  - `IsCreatedWithPromoPrice = 0`

### 8.2 Lo que realmente inserta

El insert real solo ocurre dentro de un `if` interno que vuelve a exigir la **Rama 1**:

- total exacto `= 2`
- y `count(105) = 0`

Por lo tanto:

- la **Rama 2 nunca inserta nada**
- solo permite entrar al bloque exterior
- luego el bloque interior no ejecuta el insert

En terminos funcionales, esa segunda rama es codigo inerte para otorgar FSB1.

### 8.3 Efecto de un FSB1 regular otorgado

Si inserta el `105`:

- descripcion = `'First Half'`
- actualiza `Promoters.FSB2StartDate = GETDATE()`

No actualiza `FSB2EndDate`.

## 9. Comportamiento exacto de FSB1 por extension de 14 dias

Referencia: aprox. lineas `275-290`.

Esta rama se ejecuta si:

1. no existe `CommissionTypeID = 105` desde `@FSB1StartDate`
2. `@EliteLevelExtended + count(promoters activos en @promoterExtended dentro de 14 dias) = 2`

Si cumple:

- inserta un `105`
- usa `@fsb1AmountExtended`
- descripcion `'First Half'`
- deja `FSB2StartDate = GETDATE() - 90`
- deja `FSB3StartDate = GETDATE() - 90`

### 9.1 Que significa esta rama

Es una via alternativa para otorgar la primera mitad cuando la ventana extendida de 14 dias completa exactamente 2 unidades elegibles.

### 9.2 Efecto tecnico no obvio

El update a `FSB2StartDate` y `FSB3StartDate` ocurre en tabla, pero las variables locales ya estaban cargadas al inicio del bloque.

Eso significa:

- en la misma ejecucion, las validaciones posteriores de `FSB2` y `FSB3` siguen usando los valores viejos de `@FSB2StartDate` y `@FSB3StartDate`
- el cambio a `-90` dias afecta ejecuciones futuras, no el resto de la corrida actual

## 10. Comportamiento exacto de FSB2 First Half

Referencia: aprox. lineas `293-310`.

Para insertar `CommissionTypeID = 107` deben cumplirse todas estas condiciones:

1. no existe `107` con `Creation > @FSB2StartDate`
2. existe al menos un `105` con `Creation >= @FSB1StartDate`
3. `@EliteLevel2 + count(promoters activos en @promoterfsb2 dentro de FSB2) = 2`

Luego, en el `if` interno, vuelve a exigir:

1. el mismo total exacto `= 2`
2. `count(107) = 0` desde `@FSB2StartDate`
3. existe exactamente `1` registro `105` desde `@FSB1StartDate`
4. ese `105` tiene mas de 2 minutos de antiguedad:
   - `DATEDIFF(minute, creation, GETDATE()) > 2`

Si inserta:

- crea `107`
- descripcion `'First Half'`
- actualiza `FSB3StartDate = GETDATE()`

### 10.1 Implicacion importante

El SP mete una compuerta temporal de mas de 2 minutos entre `FSB1` y `FSB2`.

Eso significa que:

- si `FSB1` se creo hace menos de 2 minutos, `FSB2` no se inserta en esa corrida
- para que `FSB2` entre, normalmente debe haber otra ejecucion posterior

## 11. Comportamiento exacto de FSB3 First Half

Referencia: aprox. lineas `316-328`.

La condicion externa acepta:

1. que no exista `109` desde `@FSB3StartDate`
2. que exista `107` desde `@FSB2StartDate`
3. que `@EliteLevel3 + count(promoters activos en @promoterfsb3) = 2`

Pero la condicion interna exige:

- `count(promoters activos en @promoterfsb3 dentro de la ventana FSB3) = 2`

Si inserta:

- crea `109`
- descripcion `'First Half'`

### 11.1 Implicacion real

Aunque la condicion externa acepta una combinacion de:

- elite externo
- mas promoters

la condicion interna solo inserta cuando hay **2 promoters reales** en `@promoterfsb3`.

En la practica:

- `FSB3` no se otorga por una mezcla `1 elite externo + 1 promoter`
- `FSB3` funciona de facto como una regla de `2 promoters`, no como regla combinada

## 12. Bloque B: reevaluacion del sponsor del promoter

Referencia: aprox. lineas `331-615`.

Despues de terminar el bloque A, el SP:

1. hace `DELETE` sobre todas las table variables
2. recarga fechas y contexto para `promoterid = @sponsorID`
3. vuelve a correr practicamente la misma logica

La intencion es que, cuando entra un promoter, tambien se reevalua si su sponsor directo ya completo algun FSB.

## 13. Diferencias entre el bloque A y el bloque B

Aunque son casi iguales, no son perfectamente identicos.

### 13.1 Diferencia en `@EliteLevel1`

Bloque A:

- repite `IsPromoCouponApplied = 0`
- no valida `IsPermanentPromoCouponApplied = 0`

Bloque B:

- si valida `IsPermanentPromoCouponApplied = 0`
- pero no filtra `FreeCommission = 0`

Resultado:

- el mismo concepto de `EliteLevel1` no se calcula igual para el promoter evaluado y para su sponsor

### 13.2 Diferencia en `@EliteLevel2`

Bloque A:

- no filtra DAG en `@EliteLevel2`

Bloque B:

- si filtra DAG en `@EliteLevel2`

### 13.3 Diferencia de descripcion en FSB1 extendido

Bloque A:

- inserta descripcion `'First Half'`

Bloque B:

- inserta descripcion `'First Half!'`

Eso deja trazas distintas para la misma logica de negocio.

## 14. Regla historica especial por fecha de enrollment

Referencia: aprox. lineas `237-242` y `533-538`.

Si el sponsor evaluado tiene `EnrollDate` entre:

- `2021-08-03 13:00:00`
- `2021-10-03 13:00:00`

entonces el SP hace:

- `FSB1EndDate + 14 dias`
- `FSB2EndDate + 7 dias`
- `FSB3EndDate + 7 dias`

### 14.1 Observacion critica

Ese ajuste ocurre **despues** de haber poblado:

- `@promoter`
- `@promoterExtended`
- `@promoterfsb2`
- `@promoterfsb3`
- `@EliteLevel1`
- `@EliteLevel2`
- `@EliteLevel3`
- `@EliteLevelExtended`

Por eso el cambio de fechas:

- no reconstuye los candidatos ya cargados
- no vuelve a contar ordenes ya medidas
- solo modifica comparaciones posteriores sobre datos ya materializados

Conclusion:

- la extension historica de fechas es parcial y probablemente no refleja completamente la intencion de negocio original

## 15. Reglas de inclusion y exclusion observables

### 15.1 Para promoters patrocinados

Se exigen normalmente:

- `FreeType = 0` o `NULL`
- `SpecialCode IS NULL`
- `Active = 1` al momento del conteo
- orden activa
- productos `20,23,25,26,27,28`
- `FreeCommission = 0`
- no DAG
- `IsCreatedWithPromoPrice = 0`

### 15.2 Para ordenes elite externas

Se usan clientes de `MWRCustomers` donde:

- `SponsorMemberID = @userid`
- `c.UserID != @userid`
- `Status = 'Active'`
- `ProductID = 20`
- `IsEliteTravelAdvantagePro = 1`
- filtros de promo segun el bloque/tramo
- filtros de DAG/FreeCommission segun el bloque/tramo

### 15.3 Exclusiones historicas por producto

En algunos conteos auxiliares se excluyen expresamente:

- `ProductID != 4`
- `ProductID != 19`
- `ProductID != 22`

### 15.4 Uso de `TOP 2`

Cada set de promoters por tramo se corta a `TOP 2` por `EnrollDate ASC`.

Eso implica:

- el SP solo mira los primeros 2 promoters elegibles por tramo
- los posteriores quedan fuera aunque tambien califiquen

## 16. Mapa real de tipos de comision

- `105` = `FSB1 First Half`
- `107` = `FSB2 First Half`
- `109` = `FSB3 First Half`

Este SP no inserta second half.  
Tampoco inserta reversals; eso vive en `PRO/FastStartBonusCancellation.sql`.

## 17. Pseudoflujo funcional resumido

```text
para promoter evaluado:
  cargar fechas FSB y usuario
  cargar promoters FSB1 / FSB1_EXT / FSB2 / FSB3
  contar elites externos por ventana
  definir monto Elite o Mixed

  si FSB1 regular cumple exactamente 2 unidades y no existe 105:
    insertar 105
    mover FSB2StartDate a ahora

  si FSB1 extendido cumple exactamente 2 unidades y no existe 105:
    insertar 105
    mover FSB2StartDate y FSB3StartDate a ahora - 90 dias

  si existe 105, pasaron > 2 minutos, no existe 107 y FSB2 suma exactamente 2:
    insertar 107
    mover FSB3StartDate a ahora

  si existe 107, no existe 109 y FSB3 suma exactamente 2:
    si hay exactamente 2 promoters en FSB3:
      insertar 109

repetir la misma idea para el sponsor directo
```

## 18. Hallazgos tecnicos importantes

### 18.1 Variables `@Mixed` y `@elite` cargadas al reves

En ambos bloques:

- `@Mixed` se carga con `FastStartBonusElite`
- `@elite` se carga con `FastStartBonusMixed`

Como luego solo se valida `@elite > 0 and @Mixed > 0`, hoy el error parece no romper el flujo.
Pero los nombres de variables no coinciden con el valor real que contienen.

### 18.2 `@ExternalOrders` es codigo muerto

Se inserta informacion ahi, pero nunca se usa para decidir pagos ni montos.

### 18.3 La rama alternativa de FSB1 con `count(105)=1` no paga nada

El `OR` del `if` externo permite entrar al bloque, pero el `if` interno solo inserta cuando `count(105)=0`.

Resultado:

- esa rama no produce ningun `INSERT`

### 18.4 `FSB3` mixto es imposible en la practica

La suma externa puede dar `2` por mezcla de elites externos y promoters.
Pero el `if` interno obliga a tener `2` promoters reales en `@promoterfsb3`.

Resultado:

- `FSB3` no funciona realmente como regla mixta

### 18.5 Se usa `= 2`, no `>= 2`

La mayoria de las compuertas de otorgamiento usan igualdad exacta:

- `elite + promoters = 2`

Eso significa que un sponsor con mas de 2 unidades elegibles puede no calificar por este SP si el conteo combinado supera `2`.

Ejemplo:

- `2 promoters + 1 elite externo = 3`
- la condicion falla por usar `= 2`

### 18.6 No hay transaccion ni locking

El SP no usa:

- `BEGIN TRAN`
- `COMMIT`
- `ROLLBACK`
- `sp_getapplock`

Eso deja riesgo de:

- doble insercion por concurrencia
- lecturas inconsistentes entre conteo e insert
- updates parciales si falla a mitad de proceso

### 18.7 La logica depende de `GETDATE()` en tiempo de ejecucion

Se usa `GETDATE()` para:

- `EarnedDate`
- `PaymentDate`
- `Creation`
- mover `FSB2StartDate`
- mover `FSB3StartDate`

Eso hace que la corrida quede anclada al momento de ejecucion, no al evento causal original.

### 18.8 Las ventanas mezclan `EnrollDate` y `OrderDate`

El SP usa:

- `EnrollDate` para promoters patrocinados
- `OrderDate` para clientes/ordenes externas elite

Eso puede generar desalineacion temporal entre las dos mitades del conteo combinado.

### 18.9 `BETWEEN` inclusivo en promoters y `< EndDate` en ordenes externas

Para promoters se usa `BETWEEN start AND end`.
Para ordenes externas se usa `>= start AND < end`.

Eso crea una semantica distinta en los limites de ventana.

### 18.10 Hay logica de rank/VIP que no termina influyendo

`@LowestRank1`, `@LowestRank2`, `@LowestRank3` y la lista de paises VIP se calculan, pero no afectan ningun insert ni monto.

## 19. Riesgos de mantenimiento y auditoria

1. El SP no es claramente idempotente bajo concurrencia.
2. La misma logica esta duplicada dos veces y no esta perfectamente sincronizada.
3. Existen divergencias reales entre el bloque del promoter y el del sponsor.
4. Hay ramas que aparentan cubrir casos especiales, pero no materializan inserts.
5. Los updates de fechas no siempre impactan la corrida actual porque las variables ya fueron cargadas.
6. La salida de auditoria depende de `DailyRealTimeCommission`, no de un modelo desacoplado de tracking.

## 20. Resumen ejecutivo

`dbo.FastStartBonus` es un SP legacy que otorga solamente **primera mitad** del FSB en produccion insertando directamente en `dbo.DailyRealTimeCommission`.

Su mecanismo real es:

- contar hasta 2 promoters patrocinados por tramo
- sumar, segun el tramo, ciertas ordenes elite externas del sponsor
- decidir si el monto es `Elite` o `Mixed`
- insertar `105`, luego `107`, luego `109`, siempre como `First Half`
- mover fechas de inicio del siguiente tramo en `dbo.Promoters`
- repetir el proceso una sola vez para el sponsor directo

Los puntos mas delicados del SQL actual son:

- codigo muerto (`@ExternalOrders`)
- variables `Elite/Mixed` invertidas
- rama alternativa de `FSB1` que no inserta
- `FSB3` mixto que en realidad no paga
- uso de `= 2` en vez de `>= 2`
- diferencias funcionales entre el bloque del promoter y el del sponsor
- ausencia de transaccion/locking

## 21. Conclusion operacional

Si la pregunta es **"que stored procedure esta otorgando hoy la primera mitad del FSB en produccion y como lo hace?"**, la respuesta es:

- es `dbo.FastStartBonus`
- inserta first half en `dbo.DailyRealTimeCommission`
- usa `105`, `107` y `109`
- evalua primero al promoter recibido y luego a su sponsor directo
- depende de ventanas FSB guardadas en `dbo.Promoters`
- combina promoters patrocinados con ciertas ordenes elite externas
- tiene varias inconsistencias heredadas que deben asumirse como parte del comportamiento actual en produccion
