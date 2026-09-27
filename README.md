# SOC_NeuralNetwork

Centro de operaciones de seguridad (SOC) de investigación que se ejecuta en local. Recibe alertas en formato Wazuh, clasifica flujos de red con modelos entrenados sobre CICIDS2017 y somete cada alerta a triaje con un LLM local (Ollama), apoyándose en conocimiento de seguridad recuperado (MITRE y runbooks). A partir de ahí correlaciona incidentes, pasa las decisiones por revisión humana, genera reglas Sigma exportables y mantiene planes de respuesta duraderos con auditoría y rollback.

> **Importante:** SOC_NeuralNetwork es una plataforma de investigación local. Antes de sacar conclusiones sobre su uso en un entorno real, lee [Estado del proyecto](#estado-del-proyecto) y [Limitaciones conocidas](#limitaciones-conocidas).


https://github.com/user-attachments/assets/8768d7db-e35e-4b53-8c2c-4d4b6ec56e06


## Índice

1. [Características](#características)
2. [Estado del proyecto](#estado-del-proyecto)
3. [Arquitectura y servicios](#arquitectura-y-servicios)
4. [Instalación nativa](#instalación-nativa)
5. [Despliegue en contenedores](#despliegue-en-contenedores)
6. [Flujo de trabajo del analista](#flujo-de-trabajo-del-analista)
7. [API y autenticación](#api-y-autenticación)
8. [Ingesta y cola de trabajos](#ingesta-y-cola-de-trabajos)
9. [Modelos de ML](#modelos-de-ml)
10. [Copias de seguridad y recuperación](#copias-de-seguridad-y-recuperación)
11. [Laboratorio de respuesta](#laboratorio-de-respuesta)
12. [Seguridad y secretos](#seguridad-y-secretos)
13. [Limitaciones conocidas](#limitaciones-conocidas)

---

## Características

- **Ingesta Wazuh**: receptor de webhooks que convierte eventos de Wazuh en trabajos de triaje, en modo síncrono o asíncrono.
- **Clasificación real de flujos**: modelos entrenados con CICIDS2017 que solo predicen cuando hay un flujo completo; nunca se inventan medidas.
- **Triaje con LLM local**: análisis con Ollama y un modelo local de 3B parámetros.
- **Conocimiento recuperado (RAG)**: runbooks y datos de MITRE indexados en una instancia embebida de Chroma.
- **Correlación de incidentes**: agrupación de alertas, predicción y simulación.
- **Revisión humana independiente**: las etiquetas de un analista las valida un revisor distinto.
- **Reglas Sigma**: generación, backtest, aprobación y exportación en YAML.
- **Planes de respuesta duraderos**: aprobación o veto, auditoría, verificación, reconciliación y rollback.
- **Cuentas persistentes** con cuatro roles: lector (*viewer*), analista (*analyst*), revisor (*reviewer*) y administrador (*administrator*).

## Estado del proyecto

**Verificado en la plataforma local:**

- Comprobaciones del flujo de trabajo completo, tanto en ejecución nativa como íntegramente en contenedores.
- Pruebas de aceptación con un navegador real.
- Laboratorio de respuesta desechable con Wazuh/Linux, con efectos observados y rollback.
- Compilación de las diez imágenes de aplicación y mantenimiento.

**Pendiente:**

- El script estricto de *smoke test* del laboratorio (tráfico HTTP, denegación de SSH y reenvío real agente → manager → SOC) todavía no ha pasado en este host.
- No se ha promovido ningún modelo candidato en esta instalación.

El detalle está en [evidencias actuales y límites de despliegue][evidencias] y en el [plan de finalización reconstruido][plan]. Los documentos de fases históricas son material de investigación, no el registro de finalización vigente.

## Arquitectura y servicios

| Puerto | Servicio | Endpoints principales |
|-------:|----------|-----------------------|
| 5050 | Dashboard | Inicio de sesión, incidentes, revisiones, administración de cuentas |
| 8002 | Receptor Wazuh | `POST /webhook`, `POST /webhook/async` |
| 8100 | Triaje | `/analyze`, `/analyze/batch`, `/analyze/async`, `/jobs/{id}` |
| 8300 | RAG | `/retrieve`, `/ingest/mitre`, `/ingest/runbooks` |
| 8400 | Feedback | Alertas, etiquetas, revisiones independientes |
| 8500 | Inferencia ML | `/predict`, `/predict/named`, `/predict/batch`, `/models/reload`, `GET /models` |
| 8600 | Correlación | Incidentes, predicción, simulación |
| 8700 | Reglas | Generación, revisión, backtest, exportación |
| 8800 | Respuesta | Planes, aprobación/veto, auditoría, verificación, reconciliación, rollback |
| 11434 | Ollama | Runtime local de modelos |

**Sobre el servicio RAG:**

- Chroma va embebido dentro del proceso autenticado del servicio RAG y no expone ningún puerto HTTP propio.
- Los embeddings los genera un modelo MiniLM fijo en formato ONNX, ejecutado en CPU.
- Los runbooks se cargan al arrancar; la ingesta de MITRE hay que lanzarla de forma explícita.
- Si la recuperación falla, no se recurre a vectores nulos ni se inventan referencias.

## Instalación nativa

En este modo, PostgreSQL se ejecuta en un contenedor aislado y el resto de servicios, incluido Ollama, de forma nativa.

### Requisitos

- Python 3.11
- Docker con Compose
- Ollama
- Runtime de OpenMP (en macOS: `brew install ollama libomp`)
- Varios GB libres de disco y memoria para el modelo local de 3B y los servicios. 16 GB de RAM es un punto de partida razonable.

### Pasos

1. **Crea el entorno virtual e instala las dependencias:**

   ```bash
   uv venv --python 3.11
   uv pip install --python .venv/bin/python \
     -r tests/requirements.txt \
     -r services/rag-service/requirements.txt \
     -r dashboard/requirements.txt
   ```

2. **Genera la configuración local:**

   ```bash
   python3 scripts/configure_local.py
   ```

   Crea un fichero `.env` con secretos aleatorios (API, base de datos, firma de identidad y firma de modelos) y un fichero privado `admin-credentials.txt` con la contraseña generada para el administrador; el propio comando indica dónde lo guarda. Si lo vuelves a ejecutar, conserva las credenciales existentes.

3. **Descarga la imagen de PostgreSQL y arranca el stack:**

   ```bash
   docker pull postgres:16-alpine
   .venv/bin/python scripts/local_stack.py up
   ```

4. **Entra en el dashboard:** abre <http://localhost:5050> e inicia sesión como `admin`.

5. **Crea las cuentas de trabajo:** desde **Account & access** (cuenta y acceso), crea cuentas separadas para el analista y el revisor.

### Gestión del stack

```bash
.venv/bin/python scripts/local_stack.py status   # ver el estado
.venv/bin/python scripts/local_stack.py down     # parar los servicios
docker compose stop postgres                     # parar PostgreSQL
```

En arranques posteriores puedes saltarte la descarga del modelo con `--skip-model-pull`.

### Conviene saber

- El lanzador guarda logs, bases de datos, cachés de modelos y registros de PID en `work/runtime`.
- En este modo, la ejecución de respuestas es **siempre** un *dry run*.
- No se instala ningún servicio de arranque automático (ni al iniciar sesión ni al arrancar el sistema).
- Esta instalación descargada usa `--state-dir ../../work/runtime` en todos los comandos nativos, y sus credenciales de administrador están en `../../work/runtime/admin-credentials.txt`. Usa siempre el mismo directorio de estado al reiniciar o al hacer copias de seguridad.

## Despliegue en contenedores

El fichero `compose.yaml` de la raíz es la configuración de referencia.

```bash
python3 scripts/container_stack.py up
python3 scripts/container_stack.py status
```

- **No lo ejecutes a la vez que la instalación nativa**: ambos usan los mismos puertos.
- Todos los puertos publicados de la aplicación se enlazan solo a loopback.
- `./deploy-SOC_NeuralNetwork.sh` y `./deploy-SOC_NeuralNetwork.ps1` usan esta misma configuración. Los ficheros heredados `docker-compose/ai-services.yml` y `docker-compose/integrated-stack.yml` la incluyen.
- El lanzador crea los contenedores, inicializa los volúmenes con nombre que estén vacíos y espera a que cada servicio esté listo. Respeta el contenido de los volúmenes existentes y no necesita compartir el sistema de ficheros del host.
- `docker compose down` conserva los volúmenes con nombre; `docker compose down -v` los **borra**.

### Importar el estado de una instalación nativa

Con los servicios nativos parados, puedes hacer una importación única añadiendo estas opciones:

```bash
python3 scripts/container_stack.py up --import-native-state --state-dir work/runtime
```

Tras la importación, el estado SQLite y los modelos de la instalación nativa y los de la de contenedores quedan separados; PostgreSQL sigue siendo compartido.

## Flujo de trabajo del analista

1. **Investigar:** revisa los incidentes y las alertas de origen.
2. **Etiquetar:** los botones *Confirm Attack* (confirmar ataque) y *False Positive* (falso positivo) guardan etiquetas. El autor que queda registrado en la auditoría es siempre la cuenta con la sesión iniciada.
3. **Previsualizar la defensa:** *Preview Defense* guarda un *dry run* con las acciones propuestas y su registro de auditoría.
4. **Revisar:** la vista *Reviews* reúne:
   - etiquetas pendientes de la decisión de un revisor distinto,
   - borradores de detección para hacer backtest, aprobar y exportar,
   - planes de respuesta interrumpidos que hay que reconciliar.

### Reglas de detección

- Cada regla debe coincidir con el evento de ejemplo que se aporta.
- Si los borradores generados por el modelo no pasan la validación, se usa una alternativa restringida de coincidencia exacta, que queda marcada como tal.
- Los backtests miden el rendimiento sobre los eventos etiquetados aportados. Sin ejemplos benignos, la tasa de falsos positivos es desconocida.
- La exportación es una descarga en YAML: no instala la regla en ningún SIEM.

### Simulaciones

Las simulaciones muestran estimaciones de investigación. Medir la prevención real o la precisión de las predicciones requiere ejercicios controlados contra un entorno real.

## API y autenticación

- Los clientes que acceden directamente a la API necesitan una credencial *bearer*.
- Un usuario humano puede obtener un token de 120 segundos que conserva su rol llamando a `POST /api/auth/token` desde el dashboard autenticado, junto con su token CSRF.
- `AI_SOC_API_KEY` es una credencial privilegiada para máquinas, no la identidad de un analista.
- Los endpoints de salud y métricas son públicos en loopback.

## Ingesta y cola de trabajos

### Recepción de alertas de Wazuh

- **Asíncrona (recomendada):** `POST :8002/webhook/async` convierte los eventos de Wazuh en trabajos de triaje duraderos y devuelve sus IDs. El resultado se consulta en `:8100/jobs/{id}`. Así no se mantienen abiertas las conexiones del emisor de Wazuh mientras dura la inferencia en CPU.
- **Síncrona:** `/webhook` sigue disponible, con un timeout acotado de 420 segundos hacia los servicios posteriores.

### Garantías de la cola

- Los trabajos asíncronos se guardan en SQLite antes de responder con HTTP 202.
- Una cola de prioridad acotada rechaza la sobrecarga con HTTP 429.
- Los trabajos sin terminar se reanudan tras un reinicio, y los resultados siguen siendo consultables.
- Los IDs de alerta hacen que la persistencia y la correlación sean idempotentes.
- Las URL de callback están deshabilitadas.
- Usa un único proceso de triaje por base de datos de trabajos y un único proceso de orquestación de respuestas por despliegue.

## Modelos de ML

### Modelos disponibles

- **Referencia en servicio:** los clasificadores binarios incluidos en el proyecto.
- **Bundle multiclase:** un bundle firmado de 15 clases, entrenado por separado sobre CICIDS2017, con un benchmark reproducible: 34 935 filas de entrenamiento y 8728 de prueba, sin solapamiento de vectores de características. Consulta los [detalles de la evaluación][evaluacion].

> El muestreo está limitado por clase y deduplicado. Son resultados dentro del mismo conjunto de datos y con pocos ejemplos en las clases raras: no demuestran generalización en un despliegue real ni mejoras derivadas del feedback.

### Entrada del clasificador

- Requiere las 77 características de flujo de CICIDS2017, todas con valores finitos. `GET /models` expone el esquema exacto.
- Las entradas con nombre normalizan los alias conocidos de CICFlowMeter y rechazan los conflictos.
- Nunca se inventan medidas de protocolo o de flujo a partir de los metadatos de la alerta. Las alertas sin un flujo completo reciben análisis del LLM, pero no predicción del modelo.

### Benchmark y reentrenamiento (nativo)

```bash
# Benchmark multiclase (fija el SHA-256 del archivo descargado)
.venv/bin/python scripts/benchmark_models.py /ruta/a/GeneratedLabelledFlows.zip \
  --output models/bundles/cicids2017-multiclass \
  --report work/multiclass-evaluation.json

# Evaluar sin promover
.venv/bin/python scripts/retrain_local.py --evaluate-only

# Reentrenar y promover con un conjunto de validación independiente
.venv/bin/python scripts/retrain_local.py --holdout /ruta/a/independent.csv --promote
```

### Reentrenamiento en contenedores

```bash
python3 scripts/retrain_container.py --evaluate-only
python3 scripts/retrain_container.py --holdout /ruta/a/independent.csv --promote
```

El contenedor de mantenimiento escribe en el mismo volumen de modelos que lee el servicio de inferencia. Al recargar se comprueba la huella exacta del artefacto verificado: una respuesta HTTP correcta que corresponda a otro bundle se rechaza.

### Garantías de integridad

- El reentrenamiento con feedback exige flujos reales y completos, etiquetas binarias aprobadas de forma independiente y un conjunto *holdout* independiente.
- Los artefactos de modelo se verifican antes de deserializarlos.
- Los bundles candidatos se firman.
- Si una promoción falla, se restauran el puntero en disco anterior y el modelo que estaba en servicio.

## Copias de seguridad y recuperación

La [guía de operaciones][operaciones] cubre roles, copias de seguridad, rollback de modelos, recuperación de respuestas y el laboratorio opcional.

```bash
.venv/bin/python scripts/local_stack.py down
.venv/bin/python scripts/backup_restore.py backup work/backups/snapshot
.venv/bin/python scripts/backup_restore.py drill work/backups/snapshot --report work/restore-report.json
.venv/bin/python scripts/local_stack.py up --skip-model-pull
```

El simulacro (`drill`) restaura PostgreSQL en una base de datos temporal nueva y valida copias de las bases de datos SQLite, sin sobrescribir el despliegue en uso.

> **Atención:** las copias de seguridad contienen secretos.

## Laboratorio de respuesta

Laboratorio opcional y desechable con Linux y Wazuh. Implementa, con intención duradera, comprobaciones de estado independientes y rollback:

- bloqueo de IP con alcance limitado,
- aislamiento de red de contenedores,
- deshabilitación de cuentas.

Su script estricto de *smoke test* comprueba además el tráfico HTTP, la denegación de SSH y el reenvío real agente → manager → SOC. **Estas comprobaciones todavía no han pasado en este host.**

## Seguridad y secretos

- `.env` y `admin-credentials.txt` contienen secretos: mantenlos privados.
- Las copias de seguridad también incluyen secretos.
- `AI_SOC_API_KEY` es una credencial de máquina privilegiada; no la uses como identidad de un analista.
- En el despliegue con contenedores, todos los puertos publicados de la aplicación escuchan solo en loopback.

## Limitaciones conocidas

- La instalación nativa solo ejecuta respuestas en modo *dry run*.
- La exportación de reglas Sigma no las instala en ningún SIEM.
- Sin ejemplos benignos, la tasa de falsos positivos de los backtests es desconocida.
- Las simulaciones son estimaciones; no miden la prevención real ni la precisión de las predicciones.
- Las métricas de los modelos son internas a CICIDS2017 y no prueban generalización en un despliegue real.
- Todavía no se ha promovido ningún modelo candidato.
- El *smoke test* estricto del laboratorio aún no ha pasado en este host.
