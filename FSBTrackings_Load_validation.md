# FSBTrackings_Load_validation.sql

## Proposito

Script de validacion tecnica para comprobar que `dbo.FSBTrackings_Load` dejo persistidos correctamente:

- el universo completo en `dbo.FSBCandidates`
- la clasificacion final en `dbo.FSBTrackings`

## Uso correcto

1. Instalar los objetos.
2. Ejecutar `dbo.FSBTrackings_Load`.
3. Ejecutar este script de validacion.

No debe correrse antes del `Load`, porque en ese caso todo el universo esperado aparecera como faltante.

## Parametros

- `@PromotionID`
- `@SponsorID = NULL`

Por defecto trae ejemplo para:

- `Code = 'FSB_2026_MAIN'`

## Que recalcula

El script vuelve a reconstruir en memoria la logica esperada de:

1. scope de sponsors
2. universo completo de candidatos
3. elegibilidad estatica
4. deduplicacion base para clasificacion
5. ventanas:
   - `FSB1`
   - `FSB1_EXT`
   - `FSB2`
   - `FSB3`
   - `NO_FSB`
6. `FirstRPHID`
7. `SecondRPHID`

## Que compara

### Universo

Compara el universo esperado contra las filas actuales de `dbo.FSBCandidates`, filtradas con `IsCurrent = 1`, mediante:

- `EXPECTED_UNIVERSE_SUMMARY`
- `ACTUAL_UNIVERSE_SUMMARY`
- `MISSING_CANDIDATE`
- `EXTRA_CANDIDATE`

### Tracking

Compara esperado vs real en `dbo.FSBTrackings` mediante:

- `EXPECTED_TRACKING_SUMMARY`
- `ACTUAL_TRACKING_SUMMARY`
- `MISSING_TRACKING`
- `EXTRA_TRACKING`
- `TRACKING_PAYLOAD_MISMATCH`

## Payload validado

Ademas de la existencia de filas, valida:

- `CustomerID`
- `ParticipantUserID`
- `CandidateType`
- `SponsorFSB1End`
- `SponsorFSB1ExtEnd`
- `SponsorFSB2Start`
- `SponsorFSB2End`
- `SponsorFSB3Start`
- `SponsorFSB3End`
- `FirstRPHID`
- `SecondRPHID`

## Que prueba del modelo actual

- universo completo `PROMOTER` y `CUSTOMER`
- soporte a `NO_FSB`
- uso de una sola orden por promoter
- uso de una sola orden por customer
- consistencia entre la carga auditada y el tracking persistido

## Resultado esperado en una corrida correcta

- `EXPECTED_UNIVERSE_SUMMARY = ACTUAL_UNIVERSE_SUMMARY`
- `EXPECTED_TRACKING_SUMMARY = ACTUAL_TRACKING_SUMMARY`
- sin filas en:
  - `MISSING_CANDIDATE`
  - `EXTRA_CANDIDATE`
  - `MISSING_TRACKING`
  - `EXTRA_TRACKING`
  - `TRACKING_PAYLOAD_MISMATCH`

## Alcance

Este script valida consistencia interna entre la logica esperada y los datos persistidos por la implementacion actual.  
No sustituye una comparacion funcional final contra el legacy.
