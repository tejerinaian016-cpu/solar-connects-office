# READY consolidado — 2026-10-10

## Resultado verificable

Job: eb5f786a-61b7-4e7c-b8af-65c7e5039d2e. Run: d0eb2421-2a08-400d-929d-dc85393570ae.
Estado canónico READY; Guardian PASS_SHADOW; score Quality 88 (umbral original 82).
do_not_publish=true, publish_blocked=true, production_candidate=false, release_gate=HOLD.
SHA256 JPEG: 1552d19fe7132678ac1a4e4fbe6e7b70ac1632ba23c10c9ff9726606aa0ca94c.
1080×1350, 171157 bytes. Copia íntegra: evidence/staging-ready-full.jpg.
Plan Quality: 117678fcbc7655f43b0342d2a7ec3add773bb98433d17b516224681f95ee2bf9.
Compilado PG JSONB: b20fedf5c97e0229e213290fa716b96bec5548a6940536bcf8ccf0885889af5d.

El dataset sintético tiene doce registros, nueve completos y tres pendientes. La aritmética se verificó en SQL. Su fuente fixture:// identifica un archivo local versionado, no una fuente real externa. Fact aprobado por verificación del fixture; no se atribuye aprobación humana ni ejecución autónoma de agentes editoriales.

Se usaron sc_creative_compile_carousel_v1, sc_quality_factory_from_run_v2 en SHADOW, worker Quality original, renderer original con fuentes locales de staging, Guardian del worker y sc_quality_shadow_record_v2 auténtico. Crítica visual realizada por el asistente sobre los JPEG completos y a 360px, vinculada por hashes; novedad limitada al corpus del laboratorio. No fue una llamada a un modelo visual externo.

**Límite importante:** el nuevo READY se materializó mediante el conector SQL autorizado y la ruta Factory SHADOW existente. No es una nueva ejecución de factory.start por JWT/ledger. La prueba previa Auth→boundary→ledger y esta prueba Renderer→Guardian→READY son evidencias separadas; todavía no prueban una ejecución productiva integral de punta a punta.

## Pruebas completadas

- Preflight y pisos geométricos originales: PASS; 11 bloques, fuente mínima 32px.
- Guardian fresco verifica bytes, dimensiones, SHA y snapshot vinculado al job; PASS_SHADOW persistido por SQL auténtico.
- Rechazos: plan modificado, bandera de publicación retirada, hash crítico inválido, ausencia de evidencia, readback mayor de diez minutos, job distinto y operación publisher.
- Post y reserva de publicación del fixture rechazados por triggers independientes de los gates.
- Rollback de la transición devolvió el job a SHADOW_RENDERING y eliminó el cambio Guardian.
- Recuperación real: se eliminaron únicamente recibos de progreso del nuevo job antes de READY; worker reconstruyó desde Storage, mismo SHA, reused=true; Guardian volvió a verificar.
- Dos llamadas concurrentes a la transición: una READY y una idempotente. Replay posterior también idempotente.
- READY sellado rechaza modificaciones. Finalizador privado sin EXECUTE para anon/authenticated/service_role.
- Worker staging-quality-job v3 cerrado, JWT requerido, HTTP 410 comprobado. No puerta operativa temporal abierta.

No se repitieron suites previas de Auth/Realtime/Office. Main y V6.1 no se modificaron. Snapshot descargado nuevamente y verificado al consolidar. El cierre muestra dos jobs totales, cero posts, cero reservas y cuatro gates OFF. Quality continúa congelado.

## Comando antiguo reconciliado

aea519fc-8b80-4880-b764-6af753623a22 tenía lease vencido desde 2026-10-09 03:56:12 UTC, permiso consumido/revocado y un borrador inválido sin assets. Se cerró FAILED mediante sc_v5_command_complete_v1 con el claim_token existente bajo locks, sin reasignar ownership ni ejecutar nuevamente. El resultado anterior está íntegro en error.previous_result; el mecanismo V5 agregó COMMAND_FAILED al audit.

No se vinculó el nuevo READY al comando anterior. Su borrador permanece intacto. Script de reconciliación idempotente: supabase/staging/reconcile-abandoned-command.sql.

La función V5 de completion original comprueba token y EXECUTING, pero no vigencia de lease ni lease_version. Para este cierre administrativo se verificaron explícitamente el vencimiento, revocación y job bajo locks. No interpretar esta reconciliación como validación de un finalizador productivo seguro frente a todos los casos de lease.

## Dependencias y recuperación

Orden SQL aplicado: guardian-contracts.sql; ready-transition.sql; guardian-reel-dependency.sql; publication-fence.sql; actualización del finalizador con timestamp fresco. El contrato de reel fue necesario para resolver la referencia SQL, aunque la prueba es de imagen. El primer ensayo detectó esa dependencia faltante; fue resuelta sin debilitar Guardian y se repitió la prueba afectada.

ready-transition.sql contiene la versión final consolidada; para instalación limpia aplicar guardian-reel-dependency antes de usar la transición. Los scripts de fixture/pruebas son exclusivamente staging y contienen IDs de la evidencia retenida.

Rollback operativo: mantener workers cerrados, gates OFF y fences; no borrar el READY ni el ledger. Git revert no revierte migraciones ni Storage. No hubo cambios productivos que revertir.

Advisor: sin ERROR; persisten RLS sin políticas (denegación por defecto), RPC SECURITY DEFINER autenticada intencional y protección de contraseñas filtradas desactivada en el laboratorio.
Referencias: [RPC privilegiada](https://supabase.com/docs/guides/database/database-linter?lint=0029_authenticated_security_definer_function_executable), [protección de contraseñas](https://supabase.com/docs/guides/auth/password-security#password-strength-and-leaked-password-protection).
