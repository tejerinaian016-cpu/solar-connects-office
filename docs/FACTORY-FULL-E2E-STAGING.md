# Factory E2E — 2026-10-10

## Resultado: PASS / GO técnico limitado al E2E de STAGING

Una misma ejecución recorrió JWT real → factory.start → ledger V5 → permiso individual → Factory/Quality V2 → renderer → Guardian → READY bloqueado → completion V5.

- Command: 5eccef28-f30e-438c-8e6c-b2e5a000fca2.
- Run: b1785a26-8d8f-4cf6-b91d-db50f3270e47.
- Job: 14c058a4-71b2-4979-8395-59565598a6e8.
- Ledger: SUCCEEDED, lease_version=2, un solo COMMAND_SUCCEEDED en audit.
- Job: READY, Guardian PASS_SHADOW, Quality 86 (umbral original 82).
- do_not_publish=true, publish_blocked=true, release_gate=HOLD.
- Plan compilado SHA256: c54fdcbad90ac9ea33bb29366d8860bd39279e529bf345bb1a7886015d25c0ea.
- Plan Quality SHA256: 4f82a273610521f1ee2c394d4eb7a7e4bbef2f16da2de16e3ca066632509dd52.
- JPEG/snapshot SHA256: ace3da0748150b0fc23b4cff29a8b452a41b728d9d60e836de5366976017dd59.
- JPEG 1080×1350, 174351 bytes, descargado y verificado también después del cierre.

Evidencia principal: evidence/factory-full-final.json; imagen: evidence/factory-full-image.jpg; Guardian: evidence/factory-full-guardian.json; snapshot/readback/cierre: evidence/factory-full-closure.json.

## Identidad y permisos

Dos usuarios sintéticos Auth, sin emails enviados ni datos productivos. Edge valida getUser y app_metadata; SQL vuelve a verificar actor autorizado, metadatos actuales y sesión vigente. No usa user_metadata. JWT/claim_token/step_token permanecen en artifacts ignorados, nunca en evidencia pública.

e2e_window preautoriza exactamente actor, command_id, run_id, hash y Quality input. START utiliza el bridge, claim, permiso, compilador, preflight y materializador Quality V2 existentes. Un único job nace en esa transacción. No se insertó el job por un camino SQL alternativo.

Cada paso adquiere una capacidad temporal de 90 segundos; progress usa un RPC restringido a service_role, exige token/version/step-token/lease vigentes y vuelve a verificar fuente inmutable y controles. El wrapper sólo permite preflight/render/guardian. El pipeline original conserva cálculos, pisos y Guardian; únicamente su escritura de progreso se encamina por ese RPC.

RECOVER exige ownership/version anterior, lease vencido y ausencia de paso vigente. Rota claim_token e incrementa lease_version tanto en ledger como permiso. Un worker obsoleto puede dejar un objeto inmutable huérfano, pero no puede persistir progreso ni completar el comando. No rematerializa.

FINISH valida Guardian fresco, ejecuta el contrato SQL auténtico y confirma READY y completion V5 en la misma transacción. Un trigger impide usar completion V5 sin pasar por el finalizador con fencing. Reconcile devuelve el resultado persistido después de una respuesta ambigua.

## Admisión y publicación

Durante la ventana, se rechazan inserts productivos de otros productores. También se interceptan updates que intenten convertir SHADOW en producción o añadir una anotación de producción tardía. El productor Quality SHADOW anterior fue ejecutado realmente dentro de una transacción revertida y continuó funcionando.

La ventana expirada sigue bloqueando otros productores mientras enabled=true, y el comando autorizado deja de avanzar. FACTORY OFF sigue siendo cierre superior: bloquea los pasos aunque el permiso individual exista. Publisher/Meta/External Write permanecieron OFF durante toda la prueba.

El fixture E2E tiene fences persistentes de flags, plan, READY sellado, posts y publish_guard. La fila singleton de e2e_window es parte de esa protección permanente: no borrarla ni reasignarla para otro ensayo. Para múltiples canarios se requiere un registro permanente por comando y revisión específica; este laboratorio es deliberadamente de un solo uso.

## Pruebas demostradas

- Cuatro START concurrentes por JWT: un command/job; no duplicados.
- JWT ausente/inválido y viewer rechazados.
- Tokens/versiones incorrectos y completion sin Guardian rechazados.
- Productor legacy productivo bloqueado; SHADOW auténtico compatible; promoción y anotación tardía rechazadas.
- Completion V5 sin wrapper y publicación directa del job rechazadas.
- Cierre de emergencia FACTORY OFF bloquea render.
- Lease vencido rechaza trabajo; RECOVER conserva job y rota a versión 2; propietario versión 1 rechazado.
- Render reintentado recupera el mismo archivo/hash. Guardian vuelve a leer bytes, dimensiones y snapshot.
- Revocación de permiso, nuevo output DIRECTOR con hash conflictivo y crítica con hash falso rechazados.
- Transacción READY+completion revertida: ledger EXECUTING y job SHADOW_RENDERING restaurados.
- FINISH real por JWT: READY+SUCCEEDED; RECONCILE mismo resultado; tres replays concurrentes de FINISH sin nuevo audit de éxito.

Las pruebas SQL de fallos/rollback usan contexto de claims controlado y están identificadas como SQL; no se presentan como autenticación JWT real. La ejecución positiva y negativas de transporte sí usan JWT real y Edge. No se hizo un benchmark exhaustivo de carreras entre todos los productores autónomos.

## Evidencia editorial real del fixture

Source fixture versionado: required_fields=[nombre,firma], nombre=EJEMPLO, firma=null; regla AND evaluada, can_close=false. No es un claim comercial ni una fuente real inventada. Stages sintéticos se aprobaron por validación del fixture, no por supuesta ejecución de agentes editoriales.

Se inspeccionó el JPEG real completo y a 360px. Crítica del asistente vinculada a hashes: claridad/legibilidad/branding correctos, layout repetido puntuado con variedad 3. Argumento AND distinto al porcentaje del fixture previo; novedad limitada al corpus de staging, con corpus canónico publicable vacío. Guardian original produjo score 86 sin bajar umbrales.

La política de rollout se habilitó sólo en staging con comparison_scope=SYNTHETIC_TEST_POLICY_NOT_PRODUCTION_APPROVAL. No representa una comparación/aprobación productiva. La aprobación Quality del archivo es la evaluación posterior real.

## Fallos encontrados y resueltos

El primer despliegue devolvió HTTP 500 antes de crear ledger/job: accessToken y auth.getUser no eran compatibles en esa instancia de cliente. Se reutilizó el patrón de Authorization del boundary existente; cuatro START pasaron después. Un test intentó modificar outputs append-only: el trigger lo rechazó; se cambió a una nueva revisión sintética dentro de rollback y se verificó el conflicto de hash.

## Cierre y límites

Gates restaurados OFF, Quality congelado/restaurado al snapshot, permiso revocado, sesiones expiradas y ventana disabled. factory-staging-e2e v3 y fixture v4 están cerrados (HTTP 410, verify_jwt=true). Cero posts y reservas. Producción no recibió ninguna escritura; main y V6.1 intactos.

Advisor sin ERROR. RPC autenticada SECURITY DEFINER es intencional, con comprobaciones internas y grants mínimos; [advertencia explicada](https://supabase.com/docs/guides/database/database-linter?lint=0029_authenticated_security_definer_function_executable). Se conserva la advertencia previa de [password protection](https://supabase.com/docs/guides/auth/password-security#password-strength-and-leaked-password-protection). RLS sin políticas deniega acceso por defecto.

**Producción continúa NO-GO para ejecutar:** esta integración está vinculada al laboratorio y a fixtures. Antes de un canario productivo: portar/revisar el cerrojo y finalizador sobre el boundary productivo, conservar fences permanentes por comando, ensayar ese paquete exacto y obtener autorización explícita de run/hash/ventana y excepción Quality. El PASS de staging no autoriza desplegar ni abrir gates.

Recuperación: preservar este comando/job y snapshots. e2e-close.sql restaura el snapshot y revoca la ventana; no borra evidencia. No reejecutar e2e-arm.sql sobre el ensayo cerrado. Scripts con IDs son evidencias de staging, no migraciones productivas.
