# FSB — Fast Start Bonus  
## Resumen Final de Implementación

**Estado:** Implementación final validada  
**Motor:** Microsoft SQL Server  
**Arquitectura:** histórica, incremental, auditable, idempotente y lista para integración productiva  
**Fecha de consolidación:** 2026-05-11

---

# 1. Objetivo del módulo

El módulo **FSB (Fast Start Bonus)** implementa el motor de calificación y generación de comisiones para:

- FSB1
- FSB1 Extension
- FSB2
- FSB3
- First Half
- Second Half

El diseño final permite:

- múltiples promociones,
- múltiples ciclos FSB por sponsor,
- histórico completo,
- reprocesamiento seguro,
- auditoría financiera,
- ejecución incremental,
- control de concurrencia,
- integración con `DailyRealTimeCommission`.

---

# 2. Regla crítica principal

Todo el motor FSB utiliza:

```sql
OrderDate
```

No se utiliza:

```sql
EnrollDate
```

`OrderDate` se usa para:

- clasificar FSB1,
- clasificar FSB1_EXT,
- clasificar FSB2,
- clasificar FSB3,
- validar ventanas,
- validar pagos de renovación.

---

# 3. Identidad del ciclo FSB

Un sponsor puede tener varios ciclos FSB.

El ciclo se identifica con:

```text
PromotionID + SponsorID + SponsorFSB1Start
```

La columna clave del ciclo es:

```sql
SponsorFSB1Start
```

Esta columna representa el inicio histórico del ciclo FSB del sponsor.

---

# 4. Modelo de datos final

## 4.1 dbo.Promotions

Define la promoción FSB.

Campos principales:

```sql
PromotionID
Code
Type
PromoName
PromoDesc
StartDate
EndDate
CreatedAt
```

Uso:

- identifica campañas FSB,
- permite múltiples promociones,
- permite histórico por promoción.

---

## 4.2 dbo.PromotionProducts

Tabla de configuración de productos de la promoción.

La implementación final usa modo de exclusión.

Ejemplo de la regla anterior:

```sql
o.ProductID NOT IN (4, 22)
```

Ahora se representa así:

```sql
PromotionID
ProductID
IsExcluded
```

Para excluir productos:

```sql
IsExcluded = 1
```

Ejemplo:

```sql
ProductID = 4
ProductID = 22
```

---

## 4.3 dbo.FSBTrackings

Tabla histórica principal.

Guarda todos los promoters clasificados en FSB:

```sql
FSB1
FSB1_EXT
FSB2
FSB3
```

Campos críticos:

```sql
PromotionID
SponsorID
PromoterID
OrderID
FSBType
SponsorFSB1Start
SponsorFSB1End
SponsorFSB1ExtEnd
SponsorFSB2Start
SponsorFSB2End
SponsorFSB3Start
SponsorFSB3End
FirstRPHID
SecondRPHID
```

### Responsabilidad

`FSBTrackings` guarda:

- promoters candidatos,
- clasificación FSB,
- ciclo del sponsor,
- primer pago asociado a la orden,
- segundo pago asociado a la orden.

### Importante

Esta tabla no decide si el pago es una renovación válida.

Solamente guarda:

```text
FirstRPHID  = primer pago SUCCESS asociado a la orden
SecondRPHID = segundo pago SUCCESS asociado a la orden
```

Ambos usando:

```sql
RecurringPaymentsHistory.CreateDate
```

---

## 4.4 dbo.FSBCommission

Tabla cabecera de comisiones FSB.

Campos principales:

```sql
PromotionID
SponsorID
SponsorFSB1Start
FSBType
HalfType
DailyRealTimeCommissionID
```

Valores válidos:

```sql
FSBType  = FSB1 / FSB2 / FSB3
HalfType = FIRST / SECOND
```

### Importante

`FSB1_EXT` no se guarda en `FSBCommission`.

Si un sponsor gana FSB1 por extensión, la comisión se guarda como:

```sql
FSBType = 'FSB1'
```

`FSB1_EXT` solo vive como clasificación histórica en:

```sql
dbo.FSBTrackings
```

---

## 4.5 dbo.FSBCommissionDetail

Tabla detalle de la comisión.

Relaciona:

```text
FSBCommission -> FSBTrackings
```

Sirve para saber exactamente qué promoters justificaron una comisión.

### First Half

Guarda todos los promoters válidos del grupo.

No guarda solamente 2.

Ejemplo:

```text
FSB1 tiene 5 promoters válidos
=> FSBCommissionDetail guarda los 5
```

### Second Half

Guarda solo los promoters con renovación válida.

---

# 5. Reglas de negocio finales

## 5.1 FSB1

El sponsor debe ingresar mínimo 2 promoters dentro de la ventana FSB1.

Si logra mínimo 2:

```text
califica FSB1 normal
habilita FSB2
```

Si ingresan más de 2 promoters, todos aplican.

---

## 5.2 FSB1_EXT

Si el sponsor no logra FSB1 normal, puede calificar en extensión.

Si logra mínimo 2 en la extensión:

```text
gana FSB1
queda excluido de FSB2
queda excluido de FSB3
```

---

## 5.3 FSB2

FSB2 solo aplica si:

```text
FSB1 fue logrado normal
```

No aplica si FSB1 fue logrado por extensión.

Debe ingresar mínimo 2 nuevos promoters.

Un promoter usado en FSB1 o FSB1_EXT no puede contar para FSB2.

---

## 5.4 FSB3

FSB3 solo aplica si:

```text
FSB2 fue logrado
```

Debe ingresar mínimo 2 nuevos promoters.

Un promoter usado en FSB1, FSB1_EXT o FSB2 no puede contar para FSB3.

---

# 6. Reglas de First Half

## 6.1 Regla general

Se paga `FIRST HALF` cuando hay mínimo 2 promoters válidos en el grupo correspondiente.

```text
FSB1 FIRST = mínimo 2 promoters FSB1 o FSB1_EXT
FSB2 FIRST = mínimo 2 promoters FSB2
FSB3 FIRST = mínimo 2 promoters FSB3
```

## 6.2 Promoters guardados

El sistema guarda todos los promoters válidos, no solo 2.

Esto permite:

- auditoría completa,
- trazabilidad financiera,
- soporte para más de 2 promoters,
- cálculo flexible de Second Half.

---

# 7. Reglas de Second Half

## 7.1 Regla final de renovación

Una renovación válida es cualquier pago asociado a:

```sql
FirstRPHID
```

o:

```sql
SecondRPHID
```

cuyo:

```sql
RecurringPaymentsHistory.CreateDate
```

esté entre 1 y 44 días desde `OrderDate`.

La regla es:

```sql
DATEDIFF(DAY, OrderDate, RecurringPaymentsHistory.CreateDate) BETWEEN 1 AND 44
```

No se usa:

```sql
PaymentMade
```

---

## 7.2 FSB1 SECOND

Debe existir:

```text
mínimo 2 promoters con renovación válida del grupo FSB1
```

---

## 7.3 FSB2 SECOND

Debe existir:

```text
mínimo 2 renovados del grupo FSB1
+
mínimo 2 renovados del grupo FSB2
```

---

## 7.4 FSB3 SECOND

Debe existir:

```text
mínimo 2 renovados del grupo FSB1
+
mínimo 2 renovados del grupo FSB2
+
mínimo 2 renovados del grupo FSB3
```

---

# 8. Stored Procedures finales

## 8.1 dbo.FSBTrackings_Load

Responsabilidad:

```text
buscar promoters candidatos
clasificarlos en FSB
guardar primer y segundo pago asociado a la orden
```

Características:

- usa `@PromotionID`,
- acepta `@SponsorID` opcional,
- usa `OrderDate`,
- no usa `EnrollDate`,
- no usa `PaymentMade`,
- usa `RecurringPaymentsHistory.CreateDate`,
- es incremental,
- es idempotente,
- usa `INSERT WHERE NOT EXISTS`,
- no borra histórico,
- usa `sp_getapplock`,
- usa transacción,
- usa `XACT_ABORT ON`,
- usa tablas temporales indexadas para performance.

### Clasificación

Clasifica:

```sql
FSB1
FSB1_EXT
FSB2
FSB3
```

con jerarquía correcta:

```text
FSB2 requiere FSB1 normal
FSB3 requiere FSB2
```

Evita que un mismo promoter/order participe en varios FSBType dentro del mismo ciclo.

### Pagos

Guarda:

```text
FirstRPHID  = primer pago SUCCESS por CreateDate
SecondRPHID = segundo pago SUCCESS por CreateDate
```

---

## 8.2 dbo.FSBCommission_Generate

Responsabilidad:

```text
generar FIRST HALF
generar SECOND HALF
insertar detalles de comisión
validar renovaciones
```

Características:

- usa `@PromotionID`,
- acepta `@SponsorID` opcional,
- usa `SponsorFSB1Start` como ciclo,
- usa todos los promoters válidos,
- no limita a 2 promoters,
- usa `FirstRPHID` o `SecondRPHID` para detectar renovación,
- usa `RecurringPaymentsHistory.CreateDate`,
- regla de renovación entre día 1 y 44,
- no usa `PaymentMade`,
- es idempotente,
- evita duplicados,
- usa `UPDLOCK`,
- usa `HOLDLOCK`,
- usa `sp_getapplock`.

---

## 8.3 dbo.FSBCommission_Report

Responsabilidad:

```text
auditar comisiones generadas
mostrar promoters usados
mostrar pagos asociados
mostrar renovación válida
mostrar fecha que justificó Second Half
```

Columnas relevantes:

```sql
FSBCommissionID
PromotionID
SponsorID
SponsorFSB1Start
CommissionFSBType
HalfType
FSBTrackingID
PromoterID
OrderID
OrderDate
TrackingFSBType
FirstRPHID
FirstRPHCreateDate
FirstRPHDays
SecondRPHID
SecondRPHCreateDate
SecondRPHDays
ValidRenewalRPHID
ValidRenewalCreateDate
ValidRenewalSource
RenewalDaysFromOrderDate
SecondHalfGrantedCreateDate
HasValidRenewal
AuditStatus
```

### Columna clave

```sql
SecondHalfGrantedCreateDate
```

Muestra el `RecurringPaymentsHistory.CreateDate` que justificó el pago del `SECOND HALF`.

---

# 9. Concurrencia e idempotencia

Los SP finales usan:

```sql
SET XACT_ABORT ON
```

y:

```sql
sp_getapplock
```

Con recursos por promoción:

```text
FSBTrackings_Load_<PromotionID>
FSBCommission_Generate_<PromotionID>
```

También usan:

```sql
UPDLOCK
HOLDLOCK
```

en los inserts idempotentes.

Esto protege contra:

- doble comisión,
- ejecución concurrente,
- duplicados,
- inconsistencias de reproceso,
- race conditions.

---

# 10. Índices principales

## 10.1 FSBTrackings

```sql
PromotionID, SponsorID, SponsorFSB1Start, FSBType
```

Incluye:

```sql
PromoterID
OrderID
FirstRPHID
SecondRPHID
CreatedAt
```

## 10.2 FSBCommission

```sql
PromotionID, SponsorID, SponsorFSB1Start, FSBType, HalfType
```

## 10.3 FSBCommissionDetail

```sql
FSBCommissionID, FSBTrackingID
```

y:

```sql
FSBTrackingID, FSBCommissionID
```

## 10.4 PromotionProducts

```sql
PromotionID, ProductID, IsExcluded
```

## 10.5 Source tables

Índices recomendados:

```sql
dbo.[Order] (Status, OrderDate, CustomerID)
dbo.RecurringPaymentsHistory (OrderID, Status, Reverted, CreateDate, ID)
dbo.Promoters (SponsorID, UserProfileID)
dbo.MWRCustomers (UserID, CustomerID)
```

---

# 11. Flujo de ejecución

## Paso 1

Crear o validar DDL:

```sql
DDL_FSB_FINAL_PRODUCTION_SAFE.sql
```

## Paso 2

Crear promoción:

```sql
dbo.Promotions
```

## Paso 3

Configurar productos excluidos:

```sql
dbo.PromotionProducts
```

Ejemplo:

```text
ProductID 4  -> IsExcluded = 1
ProductID 22 -> IsExcluded = 1
```

## Paso 4

Cargar tracking:

```sql
EXEC dbo.FSBTrackings_Load @PromotionID = 1;
```

## Paso 5

Generar comisiones:

```sql
EXEC dbo.FSBCommission_Generate @PromotionID = 1;
```

## Paso 6

Auditar:

```sql
EXEC dbo.FSBCommission_Report @PromotionID = 1;
```

---

# 12. Validaciones QA ejecutadas

Se validó que:

```text
FirstRPHID no sea igual a SecondRPHID
un mismo promoter/order no aparezca en varios FSBType
no exista FSB1 y FSB1_EXT en el mismo ciclo
FSB2 no exista sin FSB1 normal
FSB3 no exista sin FSB2
SECOND no se cree si no cumple reglas acumuladas
SECOND no falte cuando sí cumple reglas
todos los detalles SECOND tengan renovación válida
```

---

# 13. Resultados QA observados

Después de ejecutar el motor con la regla final de renovación entre día 1 y 44:

```text
FSB1 FIRST   = 2081
FSB1 SECOND  = 1036
FSB2 FIRST   = 30
FSB2 SECOND  = 16
FSB3 FIRST   = 4
FSB3 SECOND  = 2
```

Estos resultados son coherentes porque:

```text
SECOND <= FIRST
FSB3 <= FSB2 <= FSB1
```

---

# 14. Consultas de validación críticas

## 14.1 Validar que no haya duplicate FSBType por promoter/order

```sql
SELECT
    PromotionID,
    SponsorID,
    SponsorFSB1Start,
    PromoterID,
    OrderID,
    COUNT(DISTINCT FSBType) AS FSBTypeCount
FROM dbo.FSBTrackings
WHERE PromotionID = 1
GROUP BY
    PromotionID,
    SponsorID,
    SponsorFSB1Start,
    PromoterID,
    OrderID
HAVING COUNT(DISTINCT FSBType) > 1;
```

Debe devolver:

```text
0 rows
```

---

## 14.2 Validar que no haya FirstRPHID = SecondRPHID

```sql
SELECT
    FSBTrackingID,
    OrderID,
    FirstRPHID,
    SecondRPHID
FROM dbo.FSBTrackings
WHERE PromotionID = 1
  AND FirstRPHID = SecondRPHID
  AND FirstRPHID IS NOT NULL;
```

Debe devolver:

```text
0 rows
```

---

## 14.3 Validar que todo SECOND tenga renovación válida

```sql
SELECT
    fc.FSBCommissionID,
    fc.SponsorID,
    fc.SponsorFSB1Start,
    fc.FSBType,
    fc.HalfType,
    ft.FSBTrackingID,
    ft.PromoterID,
    ft.OrderID
FROM dbo.FSBCommission fc
INNER JOIN dbo.FSBCommissionDetail d
    ON d.FSBCommissionID = fc.FSBCommissionID
INNER JOIN dbo.FSBTrackings ft
    ON ft.FSBTrackingID = d.FSBTrackingID
INNER JOIN dbo.[Order] o
    ON o.OrderID = ft.OrderID
LEFT JOIN dbo.RecurringPaymentsHistory rph1
    ON rph1.ID = ft.FirstRPHID
LEFT JOIN dbo.RecurringPaymentsHistory rph2
    ON rph2.ID = ft.SecondRPHID
WHERE fc.PromotionID = 1
  AND fc.HalfType = 'SECOND'
  AND NOT
  (
        (
            rph1.ID IS NOT NULL
            AND rph1.Status = 'SUCCESS'
            AND ISNULL(rph1.Reverted, 0) = 0
            AND DATEDIFF(DAY, o.OrderDate, rph1.CreateDate) BETWEEN 1 AND 44
        )
     OR
        (
            rph2.ID IS NOT NULL
            AND rph2.Status = 'SUCCESS'
            AND ISNULL(rph2.Reverted, 0) = 0
            AND DATEDIFF(DAY, o.OrderDate, rph2.CreateDate) BETWEEN 1 AND 44
        )
  );
```

Debe devolver:

```text
0 rows
```

---

# 15. Estado final de componentes

| Componente | Estado |
|---|---|
| `DDL_FSB_FINAL_PRODUCTION_SAFE.sql` | Final |
| `dbo.FSBTrackings_Load` | Final |
| `dbo.FSBCommission_Generate` | Final |
| `dbo.FSBCommission_Report` | Final |
| Reglas FSB | Final |
| Renewal 1 a 44 días | Final |
| OrderDate-only classification | Final |
| CreateDate-only RPH evaluation | Final |
| Idempotencia | Final |
| Auditoría | Final |
| Concurrencia | Final |

---

# 16. Conclusión

La implementación FSB queda cerrada como:

```text
100% funcional
histórica
auditable
incremental
idempotente
multi-ciclo
promotion-aware
production-safe
lista para integración con payout
```

El módulo ya está preparado para integrarse con:

```sql
dbo.DailyRealTimeCommission
```

mediante:

```sql
dbo.FSBCommission.DailyRealTimeCommissionID
```

La integración con payout queda fuera del cálculo FSB y debe ejecutarse como siguiente fase.
