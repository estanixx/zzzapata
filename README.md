# ZZZapata — Google Meet Auto-Join Bot (Spec v0.2)

## 1. Objetivo

Servicio que, a una hora programada, lanza un contenedor headless-browser que:
1. Abre Chromium con una sesión de Google ya autenticada (perfil persistente).
2. Navega a la URL de la reunión de Meet.
3. Solicita unirse ("Ask to join" / "Join now").
4. Permanece conectado durante la duración esperada de la reunión.
5. Sale y el contenedor termina.

**Fuera de alcance en esta fase:** grabación, captura de audio/video, transcripción. Se agrega en fase 2.

**No incluido intencionalmente:** técnicas de fingerprint spoofing / stealth plugins para evadir detección de automatización. La estabilidad se basa en usar una cuenta real, autenticada, con perfil persistente — no en enmascarar que es un navegador automatizado.

---

## 2. Arquitectura de runtime

```
EventBridge Scheduler (cron por reunión)
        │
        ▼
   ECS Fargate Task (on-demand, RunTask vía target de EventBridge)
        │
        ├─ Container: meet-join-bot (Playwright + Chromium + Xvfb)
        │     - Perfil de Chrome persistente montado desde EFS
        │     - Credenciales/params desde SSM Parameter Store
        │     - URL de la reunión + hora fin como env vars (por task)
        │
        ├─ CloudWatch Logs (retención corta, ver §8)
        └─ EFS (persist Chrome user-data-dir entre ejecuciones)
```

### Por qué Fargate y no Lambda
Chromium + Xvfb necesitan un proceso de larga duración (la reunión puede durar 45-90 min) y filesystem persistente. Lambda tiene límite de 15 min.

### Por qué EFS y no efímero
Sin perfil persistente, cada ejecución sería un "primer login" de Chrome, lo cual dispara verificaciones adicionales de Google. Con perfil persistente en EFS, la sesión se mantiene igual que si fuera el mismo navegador de siempre.

---

## 3. Estrategia de branching y control de versiones

**Modelo: trunk-based development.** `main` es la única rama de larga duración y siempre debe quedar deployable. Todo cambio pasa por una rama corta + PR.

### 3.1 Naming de ramas

```
<tipo>/<descripcion-corta-en-kebab-case>
```

Tipos permitidos: `feat`, `fix`, `chore`, `infra`, `ci`, `docs`, `refactor`.

Ejemplos:
- `infra/add-efs-chrome-profile`
- `fix/join-timeout-handling`
- `ci/add-checkov-scan`

Reglas: sin mayúsculas, sin espacios, vida corta (objetivo: mergear en <2-3 días para minimizar drift respecto a `main`).

### 3.2 Naming de PRs

Título del PR = Conventional Commits format:

```
<tipo>(<scope opcional>): <descripción en imperativo>
```

Ejemplos:
- `infra(ecs): add fargate task definition for join-bot`
- `fix(bot): handle "ask to join" approval timeout`
- `ci: run checkov on terraform plan`

Descripción del PR debe incluir: qué cambia, por qué, y (si aplica) el `terraform plan` resumido — el pipeline de PR lo publica automáticamente como comentario, no hace falta pegarlo a mano.

### 3.3 Naming de commits

Conventional Commits estricto:

```
<tipo>(<scope opcional>): <resumen en imperativo, minúsculas, sin punto final>

[cuerpo opcional explicando el porqué]
```

Tipos: `feat`, `fix`, `chore`, `infra`, `ci`, `docs`, `refactor`, `test`.

Se recomienda squash-merge en el PR para que el historial de `main` quede un commit por PR, con el título del PR como mensaje final.

---

## 4. Estructura del repositorio

```
zzzapata/
├── bootstrap/                    # infra prerequisito, se aplica una sola vez / rara vez
│   ├── backend.tf                # backend propio (state key separado)
│   ├── providers.tf
│   ├── ecr.tf                    # repo de imagenes del bot
│   ├── github_oidc.tf            # data source al OIDC provider existente (no se crea uno nuevo)
│   ├── iam.tf                    # roles OIDC (plan/apply) + permissions boundaries
│   ├── variables.tf
│   └── outputs.tf
│
├── environments/
│   └── prod/                     # infra de runtime real
│       ├── backend.tf            # key = zzzapata/prod/terraform.tfstate
│       ├── providers.tf
│       ├── main.tf               # llama a modules/
│       ├── variables.tf
│       ├── terraform.tfvars
│       └── outputs.tf
│
├── modules/
│   ├── ecs-join-bot/              # cluster, task def, sg, iam de tarea
│   ├── efs-chrome-profile/
│   └── scheduler/                 # schedule group + schedules
│
├── container/
│   ├── Dockerfile
│   ├── join_bot.py
│   ├── entrypoint.sh
│   └── requirements.txt
│
├── .github/
│   └── workflows/
│       ├── ci.yml                 # reusable workflow (workflow_call)
│       ├── pr.yml                 # PR: llama ci.yml + terraform plan
│       └── cd.yml                 # push a main: llama ci.yml + apply + build/push imagen
│
└── README.md
```

### Por qué separar `bootstrap/` de `environments/prod/`
`bootstrap` crea los recursos que el propio pipeline de CI/CD necesita para funcionar (ECR, rol OIDC, lock table) — no se pueden gestionar con el mismo pipeline que dependen de ellos (problema de huevo-y-gallina). Se aplica manualmente o con un pipeline separado y de ejecución infrecuente. `environments/prod` es la infra de negocio propiamente dicha, gestionada por el CD normal en cada merge a `main`.

Ambos usan el mismo bucket de state (`central-tfstate-estanix-871696174477`) pero **keys distintas**:
- `zzzapata/bootstrap/terraform.tfstate`
- `zzzapata/prod/terraform.tfstate`

---

## 5. CI/CD

### 5.1 Autenticación (costo $0, sin llaves de larga duración)
GitHub Actions se autentica a AWS vía **OIDC** (rol IAM `zzzapata-github-actions`, creado en `bootstrap/github_oidc.tf`), no con access keys guardadas en secrets de GitHub. Sin costo adicional, y elimina el riesgo de credenciales estáticas filtradas.

### 5.2 `ci.yml` — reusable workflow (`workflow_call`)
Invocado tanto por `pr.yml` como por `cd.yml` (siempre corre CI antes de cualquier plan/apply real):

1. `terraform fmt -check -recursive`
2. `terraform init` + `terraform validate` (en `environments/prod`)
3. `tflint` (gratis, OSS)
4. `checkov` sobre el plan (gratis, OSS) — chequeos de seguridad/costo básicos
5. `docker build` del contenedor del bot (valida que el Dockerfile compila, no se pushea nada acá)

### 5.3 `pr.yml` — pipeline de cada PR
Trigger: `pull_request` hacia `main`.
1. Llama a `ci.yml`
2. `terraform plan` en `environments/prod` (usa el rol OIDC en modo solo-lectura/plan)
3. Publica el plan como comentario en el PR
4. **No aplica nada, no pushea imagen**

### 5.4 `cd.yml` — pipeline de deployment
Trigger: `push` a `main` (post-merge).
1. Llama a `ci.yml` (mismo chequeo, nunca se saltea)
2. `terraform apply -auto-approve` en `environments/prod`
3. `docker build` + tag `<git-sha>` (únicamente — el repo ECR es `IMMUTABLE`, no admite tags mutables como `latest`) + push a ECR
4. Si cambió el hash de la imagen, fuerza nueva `task_definition` revision (Terraform ya lo maneja si el `image` tag está parametrizado con el sha)

Ambos pipelines (`pr` y `cd`) corren sobre el mismo `environments/prod` — no hay ambiente de staging en esta fase; si se necesita luego, se agrega `environments/staging/` con su propio state key y se replica el patrón.

---

## 6. Manejo de secretos — SSM Parameter Store

Se usa **Parameter Store (Standard tier, SecureString con la KMS key `alias/aws/ssm` por defecto)** en vez de Secrets Manager: incluido en el free tier de SSM, sin costo mensual por parámetro (Secrets Manager cobra ~$0.40/secreto/mes + $0.05 por 10k API calls).

Convención de paths:
```
/zzzapata/prod/bot/session-backup     (si aplica, SecureString)
/zzzapata/prod/bot/meeting-url        (String, si se necesita fuera del evento de Scheduler)
```

- **No** se guardan usuario/contraseña de la cuenta del bot como flujo normal.
- Login inicial: manual, una sola vez, poblando el perfil persistente en EFS (incluye 2FA si aplica).
- Ejecuciones normales: reusan el perfil en EFS, sin necesidad de leer credenciales.
- Si la sesión expira, el bot falla explícitamente y notifica — no reintenta login automático.
- IAM: el rol de la tarea (`ecs_task`) solo tiene `ssm:GetParameter` scoped a `/zzzapata/prod/*`, nunca `*`.

---

## 7. Optimización de costos

| Decisión | Motivo |
|---|---|
| Fargate on-demand (no Spot) para el join-bot | Una interrupción de Spot a mitad de una reunión es peor que el ahorro; Fargate ya es pay-per-use (cero costo si no hay tarea corriendo) |
| Subnet pública + IP pública en la tarea, sin NAT Gateway | NAT Gateway cuesta ~$32/mes + data processing, fijo, incluso sin uso. Una tarea efímera con SG restrictivo (solo egress 443) no lo necesita |
| EFS en modo Bursting Throughput (no Provisioned) | Provisioned cobra por MB/s reservado; el perfil de Chrome es pequeño y de acceso esporádico |
| SSM Parameter Store (Standard) en vez de Secrets Manager | Gratis vs. ~$0.40/secreto/mes |
| CloudWatch Logs retention: 14 días | Evita acumulación de storage cost indefinido |
| ECR lifecycle policy: mantener solo últimas 5-10 imágenes | Evita costo de storage de imágenes viejas |
| GitHub OIDC en vez de credenciales estáticas | No es un costo directo, pero evita rotación manual/tooling adicional |
| EventBridge Scheduler | Sin costo por schedule inactivo, se cobra por invocación |

---

## 8. Contenedor (`container/`)

**Base image:** `mcr.microsoft.com/playwright/python:v1.4x-jammy` (o equivalente Node), ya trae Chromium + dependencias.

**Dockerfile — elementos clave:**
- Instalar `xvfb`
- `entrypoint.sh`: `Xvfb :99 -screen 0 1280x720x24 &` → `export DISPLAY=:99` → ejecutar el script
- Montar `/data/chrome-profile` como volumen (EFS) → usarlo como `user_data_dir` de Playwright (`launch_persistent_context`)

**`join_bot.py` — flujo lógico:**
1. Leer env vars: `MEETING_URL`, `MEETING_END_ISO`, `BOT_DISPLAY_NAME`.
2. `launch_persistent_context(user_data_dir="/data/chrome-profile", headless=False)` — headed real sobre Xvfb.
3. Verificar sesión activa; si no hay login, fallar con log claro.
4. Navegar a `MEETING_URL`, manejar "Join now" / "Ask to join" con polling y timeout configurable.
5. Loop de keep-alive hasta `MEETING_END_ISO` o hasta detectar salida de la reunión.
6. Cerrar contexto limpiamente (persistencia correcta de cookies en EFS).

---

## 9. Variables de entrada esperadas (`environments/prod/variables.tf`)

```hcl
variable "project_name" {
  default = "zzzapata"
}

variable "aws_region" {
  default = "us-east-1"
}

variable "vpc_id" {
  type = string
}

variable "public_subnet_ids" {
  description = "Subnets publicas para la tarea (sin NAT, con IP publica asignada)"
  type        = list(string)
}

variable "task_cpu" {
  default = 1024
}

variable "task_memory" {
  default = 2048
}
```

---

## 10. Pendiente de definir con el usuario

- ¿Reuniones recurrentes (mismo horario semanal) o ad-hoc? Cambia el diseño del scheduler (schedule recurrente vs. creado dinámicamente vía API/Lambda).
- ¿Quién dispara la creación de cada schedule? Terraform estático vs. una Lambda/API que los agrega desde un calendario.
- Nombre real de la VPC/subnets públicas a usar, o si hay que crear una VPC nueva mínima solo para este proyecto.
- Notificación de fallos: ¿SNS a email, Slack webhook, otro?
- ¿El repo ya existe en GitHub? Necesito el `org/repo` exacto para configurar el OIDC trust policy en `bootstrap/github_oidc.tf`.

---

## 11. Nota de cumplimiento

Este bot entra a la reunión como un participante autenticado más — sujeto a los Términos de Servicio de Google Meet igual que cualquier asistente automatizado. Cuando se agregue grabación en fase 2, conviene verificar que los participantes vean el aviso de "esta reunión se está grabando" que Meet muestra automáticamente, más allá del permiso del organizador.
