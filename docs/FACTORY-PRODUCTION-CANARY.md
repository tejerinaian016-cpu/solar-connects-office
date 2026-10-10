# Procedimiento de un único canario — PREPARADO, NO AUTORIZADO

Estado: NO-GO productivo. Producción akwqkymjrovqiijnhrqs permanece exclusivamente lectura, gates OFF y Quality STAGE1_FROZEN_OBSERVATION. Este documento no habilita ejecución ni constituye un script de despliegue.

## Bloqueos técnicos concretos

1. El READY aprobado es SHADOW de staging, creado por SQL autorizado; falta demostrar una misma ejecución JWT factory.start → ledger → materialización → worker → Guardian → READY bloqueado → completion del mismo comando.
2. La apertura global FACTORY permite a productores legacy no reservados continuar por sus contratos. El aislamiento por run de factory.start no demuestra exclusividad global durante esa ventana. No abrir el gate hasta tener un cerrojo de admisión temporal que rechace cualquier producción fuera del permiso individual, incluyendo Factory autónoma, y conservar el kill switch superior.
3. El finalizador staging_ready está limitado a un fixture y una identidad local; no debe copiarse a producción. El contrato productivo Quality package existente habilita flags de publicación. Hace falta un finalizador de canario con evidencia Guardian auténtica y snapshot fresco que mantenga HOLD, do_not_publish y publish_blocked, con fence permanente por job.
4. Completion V5 original no exige lease vigente/lease_version. El bridge productivo debe cerrar mediante fencing de ownership/version y reconciliación explícita de lease vencido; un timeout nunca implica éxito ni permite rematerializar.

## Próximo cambio a implementar y probar sólo en staging

Unificar el permiso existente con un finalizador bloqueado: autorización individual persistida con command_id, actor, idempotency_key, creative_run_id, compiled_plan_sha256, quality_input_sha256, claim_token, lease_version, expiry, policy_epoch, max_jobs=1 y stop_at=READY. El worker toma estos valores desde la base; no acepta plan/job arbitrario. Renovación de lease mediante compare-and-swap o reconciliación con fencing, nunca sustitución silenciosa de ownership.

El cerrojo temporal global debe ser adicional: gate FACTORY OFF siempre deniega; gate ON requiere autorización individual cuando el cerrojo está armado. Todos los productores productivos deben pasar por la misma comprobación transaccional, incluidos inserts seguidos de anotación tardía. SHADOW legítimo queda separado. Expiración/revocación cierra admisión. Probar carreras entre legacy/canario y cierre de emergencia, sin abrir gates productivos.

Para READY, verificar dentro de transacción plan/run/claim/version, Guardian durable, hash del conjunto de assets y lectura reciente; conservar evidencia immutable, fences de publicación y job ID. Completion exitoso sólo después del commit READY del mismo job; reconciliación devuelve ese resultado si se pierde la respuesta. Probar interrupciones antes y después de cada commit. No trasladar aprobaciones sintéticas a hechos comerciales.

## Paquete de autorización futura (Ian debe aprobar valores concretos)

- Identidad del operador y único command_id/idempotency_key.
- Run nuevo aprobado con hechos reales trazables; hash de compilado y Quality; fecha de expiración.
- Una pieza/formato y límite USD 0 verificable, recursos existentes, sin servicios pagos.
- Versión exacta del código revisado y migration/rollback ensayados.
- Excepción individual y temporal al freeze Quality aprobada explícitamente, con policy_epoch y slot; no descongelamiento general.
- Apertura FACTORY acotada únicamente después de probar exclusividad y mecanismo de cierre; Publisher, Meta y External Write siempre OFF.
- Guardian real, READY bloqueado, cero publicación y criterio de aborto.

## Secuencia futura, únicamente tras resolver bloqueos y recibir autorización

1. Guardar snapshot de funciones/ACL/gates/policy y hash de HEAD. Desplegar código con gates OFF; comprobar permisos y fence.
2. Crear autorización exacta y limitada. Activar sólo su admisión Quality y ventana FACTORY bajo el cerrojo probado.
3. Reclamar y materializar atómicamente una vez. Registrar job ID; ante respuesta ambigua reconciliar ledger, no reintentar con otro id.
4. Cerrar inmediatamente la admisión FACTORY tras materializar; trabajo en curso requiere su permiso vigente y cierre de emergencia efectivo.
5. Render, lectura de Storage, validación visual/hash/semántica, Guardian y READY bloqueado. Si algo falla: HOLD/FAILED con evidencia, jamás PASS inferido.
6. Completar ledger, revocar permiso, restaurar snapshots de controles temporales, confirmar gates OFF, Quality congelado y cero publicaciones nuevas.

Rollback: primero cerrar admisión y detener worker; preservar ledger/job/Storage. Restaurar únicamente configuración y versiones capturadas, sin borrar evidencia ni retirar el fence de publicación del canario. Ensayar antes en staging. Una falla de cierre es bloqueo crítico y prohíbe continuar.
