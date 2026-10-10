# Factory: candidato reversible, sin autorización de ejecución

Fecha: 2026-10-10. Base aprobada: `8f73ae0b9a72501328eaa6f8737d7fff573471fb`.
Único destino modificado: STAGING `cmwervbwxyqzowntnxwe`. Producción sólo lectura.

## Adaptación

El generador `tools/build-factory-canary.cjs` reutiliza el boundary JWT, ledger, worker y finalización del E2E aprobado. Genera SQL y Edge con manifiesto SHA256. No rediseña Office ni cambia main.

- Registro permanente por command_id, run único y como máximo una autorización activa. Identidad, plan, Quality, policy_epoch, expiración y evidencia de autorización inmutables.
- Aprobación exacta ligada a actor/run/command/hash/Quality hash/epoch/expiración, max_jobs=1 y stop_at=READY. Sin API pública de activación.
- Cerrojo transaccional compartido para productores y exclusivo para activación/operaciones de control. Conserva SHADOW legítimo; bloquea productores no autorizados y anotaciones tardías de producción.
- Permiso consumido dentro de la misma transacción de materialización; ownership, claim_token, lease_version y step_token preservados.
- FACTORY OFF sigue siendo cierre superior. Freeze o cambio de epoch de Quality impide avanzar. No hay excepción a gates.
- READY conserva do_not_publish, publish_blocked, release_gate=HOLD y PASS_SHADOW auténtico. No equivale a aprobación para publicar. Fences de publicaciones persisten para autorizaciones archivadas.
- Edge requiere habilitación explícita y project_ref coincidente con SUPABASE_URL; por defecto HTTP410. Privilegios de ejecución retirados en el laboratorio después de las pruebas.

## Evidencia nueva (sin repetir E2E previo)

- `evidence/canary-adaptation-sql.json`: 9 PASS contra contratos restaurados en STAGING; autorización exacta, exclusividad, legacy, SHADOW, inmutabilidad, no rearmado, fence archivado y grants.
- `evidence/canary-adaptation-runtime.json`: 5 PASS; replay al mismo job, gate superior, freeze/epoch, ownership válido y lease obsoleto. Contexto SQL transaccional con rollback, NO nuevo JWT E2E.
- `evidence/canary-adaptation-concurrency.json`: dos conexiones PostgREST/backend distintos; productor esperó 1,492663 s y adquirió después de liberar el holder. Inserción de prueba revertida.
- Desinstalación con registro vacío y reinstalación del paquete exacto ejecutadas exitosamente; luego rollback operativo y suite SQL de 9 casos PASS sobre paquete reinstalado.
- `evidence/canary-adaptation-edge-closed.json`: Edge candidato v1 desplegado únicamente en staging, verify_jwt=true, respuesta real 410 CANARY_DISABLED.
- `evidence/canary-adaptation-final-gates.json`: cuatro gates OFF. `final.json`: registro vacío y permisos de ejecución false; cero posts. Conteo de jobs pasó de 3 a 4 durante trabajo concurrente ajeno; este paquete no atribuye ni valida ese cuarto job. Ninguna prueba de este paquete retuvo nuevos jobs/renders.
- Helper temporal de concurrencia sin grants a anon/authenticated/service_role. No conservar credenciales en Git.

Los fallos iniciales de instrumentación (dollar quoting, alias ambiguo y timeout de probe) se corrigieron antes de los PASS; no son aprobaciones omitidas. El primer intento de carrera por conector serializado fue inconcluso y se sustituyó por conexiones HTTP reales.

## Orden futuro de instalación — requiere autorización separada

1. Capturar definiciones, ACL, triggers, gates y Quality antes de cualquier despliegue autorizado. Comprobar hashes del manifiesto y ausencia de otra ventana/worker activo.
2. Instalar primero `supabase/candidate/factory-isolation.sql` si falta. La lectura productiva encontró factory_assert y factory_materialize ausentes; claim/complete V5 y funciones Quality V2 presentes. No aplicar por este documento.
3. Instalar `factory-canary-install.sql` con registro vacío. Desplegar `factory-canary-edge.ts` con pipeline.ts, parser.ts, quality.mjs y quality-render.ts aprobados, exclusivamente con recursos del proyecto destino. Mantener FACTORY_CANARY_ENABLED=false; aplicar rollback operativo hasta una autorización individual.
4. Preparar un run legítimo APPROVED de menos de 24 horas, sin job previo, pasado por Radar/Editor/Director y preflight. Compilar y congelar plan y Quality. Elegir actor v5_operator, command_id, idempotency_key, ventana y policy_epoch exactos.
5. Solicitar autorización humana de esos valores, max_jobs=1, coste incremental cero, parada READY, cambios temporales específicos de FACTORY y Quality y su restauración. Guardar referencia verificable de esa autorización. Publisher/Meta/External Write permanecen OFF.
6. Sólo tras autorización: activar registro y cerrojo antes de abrir FACTORY/Quality en una transacción administrativa con lock 701628340; conceder únicamente los grants de ejecución previstos. Verificar ningún productor puede escapar del permiso. Habilitar worker limitado al proyecto. Si no puede aislarse algún productor o dependencia, abortar sin abrir gates.
7. Ejecutar comando autenticado y pasos existentes hasta Guardian/READY/completion del mismo comando, cotejando identidades, hashes y Storage. Ante respuesta ambigua consultar estado/reconciliar con fencing; nunca crear nuevo comando para reintentar.
8. En éxito o error: cerrar Edge, aplicar rollback operativo, restaurar exactamente snapshots de gates/Quality, comprobar cero publicaciones y permisos/leases cerrados. Conservar registros, evidencias y fences.

## Rollback

`factory-canary-uninstall-unused.sql` elimina sólo objetos propios y únicamente con registro vacío. Probado en staging. Después de cualquier autorización, usar `factory-canary-rollback.sql`: revoca ejecución/permiso y deshabilita ventana sin borrar historial ni fences. No elimina la infraestructura base ni modifica contratos V5. Un rollback del paquete no revierte automáticamente gates/Quality externos: su restauración desde snapshots y cierre de Edge son obligatorios.

## Decisión

Preparación técnica delta validada en STAGING; NO-GO para ejecutar o solicitar autorización de un canario productivo concreto hoy. Lectura productiva dirigida: cero runs APPROVED frescos (<24 h) sin job, y base de aislamiento aún no desplegada. No existe todavía tupla individual run/plan/hash para aprobar. Tampoco hay autorización para descongelar Quality o abrir FACTORY.

Próximo paso mínimo: preparar, bajo autorización separada para las escrituras productivas necesarias, un run editorial legítimo fresco y su plan inmutable; presentar la tupla exacta y ventana junto con este paquete para aprobación individual. Hasta entonces no instalar ni activar nada en producción. El E2E JWT previo permanece como evidencia heredada; este candidato sólo afirma las pruebas delta detalladas arriba.
