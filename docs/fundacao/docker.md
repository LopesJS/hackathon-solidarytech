# SolidaryTech — Guia de Containerização

Documentação técnica completa sobre a estratégia de containerização dos microsserviços da plataforma SolidaryTech, incluindo decisões de arquitetura, boas práticas de segurança e roadmap de evolução do deploy.

---

## Índice

1. [Visão Geral da Estratégia](#visão-geral-da-estratégia)
2. [Análise por Serviço](#análise-por-serviço)
   - [ngo-service (Python/Flask)](#ngo-service-pythonflask)
   - [donation-service (Go)](#donation-service-go)
   - [volunteer-service (Python/Flask)](#volunteer-service-pythonflask)
3. [Boas Práticas Aplicadas](#boas-práticas-aplicadas)
4. [Variáveis de Ambiente e Segredos](#variáveis-de-ambiente-e-segredos)
5. [Fase 1 — Testes na AWS (ECS/ECR)](#fase-1--testes-na-aws-ecsecr)
6. [Fase 2 — Evolução para Kubernetes (EKS)](#fase-2--evolução-para-kubernetes-eks)
7. [Comandos de Referência Rápida](#comandos-de-referência-rápida)

---

## Visão Geral da Estratégia

Todos os três Dockerfiles adotam **multi-stage build** como padrão. Essa técnica divide o processo em dois estágios:

| Estágio | Responsabilidade | Permanece na imagem final? |
|---|---|---|
| `builder` | Compilar código, baixar dependências, gerar artefatos | ❌ Não |
| `runtime` | Executar a aplicação com o mínimo necessário | ✅ Sim |

### Por que multi-stage?

- **Imagens menores**: o `builder` carrega compiladores, `pip`, `go`, headers — nada disso vai para produção.
- **Menor superfície de ataque**: menos pacotes = menos CVEs.
- **Build reprodutível**: o ambiente de build não contamina o ambiente de execução.

---

## Análise por Serviço

### ngo-service (Python/Flask)

**Imagem base escolhida:** `python:3.11-slim`

`slim` é a versão do Debian sem pacotes desnecessários (man pages, locales, etc.). Preferido sobre `alpine` para Python porque o `alpine` usa `musl libc`, que pode causar incompatibilidades com extensões C (como `psycopg2`).

**Decisões técnicas:**

| Decisão | Justificativa |
|---|---|
| `python:3.11-slim` em ambos os estágios | Compatibilidade com `psycopg2-binary` (driver C para PostgreSQL) |
| `pip install --prefix=/install` no builder | Isola as libs instaladas para cópia limpa no runtime |
| `libpq5` instalado no runtime | Dependência de sistema do `psycopg2` em tempo de execução |
| `gunicorn` com 2 workers | WSGI production-ready; o `flask run` é apenas para desenvolvimento |
| Usuário `appuser` (uid 1001) | Nunca executar como `root` dentro do container |

**Variáveis de ambiente obrigatórias:**

```env
DATABASE_URL=postgres://usuario:senha@host:5432/ngo_db
PORT=8081          # opcional, padrão 8081
```

---

### donation-service (Go)

**Imagem base escolhida:** `golang:1.21-alpine` (builder) + `gcr.io/distroless/static-debian12:nonroot` (runtime)

Esta é a configuração mais segura possível para um serviço Go. A imagem **distroless** do Google não contém shell (`/bin/sh`), package manager, ou qualquer utilitário Unix. É apenas o runtime mínimo do sistema operacional + o seu binário.

> ⚠️ O `donation-service` é o **hot path** da plataforma (componente crítico). A escolha da distroless é deliberada: minimiza radicalmente a superfície de ataque.

**Decisões técnicas:**

| Decisão | Justificativa |
|---|---|
| `CGO_ENABLED=0` | Binário estático, sem dependência de libc do host |
| `-ldflags="-s -w"` | Remove tabelas de debug e símbolos → binário ~30% menor |
| `-trimpath` | Remove paths do sistema de build do binário → menos metadados expostos |
| `distroless:nonroot` | Sem shell = sem possibilidade de execução de comandos arbitrários |
| Cópia de `ca-certificates` | Necessário para conexões TLS com AWS SQS/RDS |
| Cópia de `zoneinfo` | Necessário para parse correto de timestamps com timezone |

**Pré-requisito antes do build:**

O `go.sum` não estava presente no repositório. Antes de fazer o `docker build`, gere-o localmente:

```bash
cd donation-service
go mod tidy   # gera/atualiza o go.sum
```

Depois atualize o `Dockerfile` para incluir a linha `COPY go.sum ./`.

**Variáveis de ambiente obrigatórias:**

```env
DATABASE_URL=postgres://usuario:senha@host:5432/donation_db
PORT=8082               # opcional, padrão 8082
AWS_REGION=us-east-1
AWS_SQS_URL=https://sqs.us-east-1.amazonaws.com/ACCOUNT_ID/QUEUE_NAME
```

---

### volunteer-service (Python/Flask)

**Imagem base escolhida:** `python:3.11-slim`

Estrutura idêntica ao `ngo-service`, porém sem `libpq5` (não usa PostgreSQL). Usa `boto3` para comunicação com DynamoDB.

**Decisões técnicas:**

| Decisão | Justificativa |
|---|---|
| `python:3.11-slim` | Compatibilidade e tamanho equilibrado |
| Sem libs de sistema extras | `boto3` opera via HTTPS, sem dependências nativas |
| IAM Role para credenciais AWS | **Nunca** usar `AWS_ACCESS_KEY_ID` / `AWS_SECRET_ACCESS_KEY` em produção |
| `gunicorn` com 2 workers | Produção-ready; workers configuráveis via env |

**Variáveis de ambiente obrigatórias:**

```env
AWS_REGION=us-east-1
AWS_DYNAMODB_TABLE=SolidaryTechVolunteers
PORT=8083              # opcional, padrão 8083
```

---

## Boas Práticas Aplicadas

### ✅ Segurança

| Prática | Aplicado em |
|---|---|
| Usuário não-root (`appuser` / `nonroot`) | Todos os serviços |
| Imagem base `slim` ou `distroless` | Todos os serviços |
| Sem `sudo`, sem `root` em runtime | Todos os serviços |
| Credenciais AWS via IAM Role (não em env vars) | `volunteer-service`, `donation-service` |
| `-trimpath` remove metadados do build | `donation-service` |
| Sem shell em produção (`distroless`) | `donation-service` |

### ✅ Eficiência de Build (Cache)

O Docker reutiliza camadas em cache. A ordem de `COPY` é crítica:

```dockerfile
# ✅ CORRETO — dependências primeiro (mudas raramente)
COPY requirements.txt .
RUN pip install ...
COPY app.py .           # código muda frequentemente → camada mais externa

# ❌ ERRADO — invalida cache a cada mudança de código
COPY . .
RUN pip install -r requirements.txt
```

### ✅ Health Checks

Todos os serviços possuem `HEALTHCHECK` definido no Dockerfile, compatível com:
- `docker run` e `docker-compose`
- AWS ECS (health check do container)
- Kubernetes liveness/readiness probes (configurado no manifest, não no Dockerfile)

### ✅ Labels OCI

Todos os Dockerfiles incluem labels padronizadas conforme a [OCI Image Spec](https://specs.opencontainers.org/image-spec/annotations/):

```dockerfile
LABEL org.opencontainers.image.title="..."
      org.opencontainers.image.description="..."
      org.opencontainers.image.version="1.0.0"
```

Em CI/CD, adicione também:
```
org.opencontainers.image.source=https://github.com/org/repo
org.opencontainers.image.revision=$GIT_SHA
org.opencontainers.image.created=$BUILD_DATE
```

### ✅ `.dockerignore`

Crie um `.dockerignore` em cada serviço para evitar que arquivos locais contaminem o contexto de build:

```
# ngo-service/.dockerignore e volunteer-service/.dockerignore
__pycache__/
*.pyc
*.pyo
.env
.env.*
*.egg-info/
.pytest_cache/
.venv/
venv/

# donation-service/.dockerignore
*.exe
*.test
.env
.env.*
/vendor/
```

---

## Variáveis de Ambiente e Segredos

### Hierarquia de segurança (melhor → pior)

```
IAM Role (ECS Task Role / EKS IRSA)     ← ✅ Use isso em AWS
  │
AWS Secrets Manager + env inject        ← ✅ Para DATABASE_URL
  │
AWS SSM Parameter Store                 ← ✅ Boa alternativa
  │
Variáveis de ambiente no container      ← ⚠️ Aceitável para não-segredos
  │
.env file no repositório                ← ❌ NUNCA commitar
  │
Credenciais hardcoded no Dockerfile     ← ❌ NUNCA fazer isso
```

### Credenciais AWS (`volunteer-service` e `donation-service`)

Em vez de passar `AWS_ACCESS_KEY_ID` e `AWS_SECRET_ACCESS_KEY` como variáveis de ambiente:

**No ECS:** configure uma **ECS Task Role** com as permissões mínimas necessárias (DynamoDB:GetItem, SQS:SendMessage, etc.). O SDK da AWS (`boto3`, `aws-sdk-go`) detecta automaticamente as credenciais via IMDSv2.

**No EKS:** use **IRSA (IAM Roles for Service Accounts)** — associa um IAM Role a um Kubernetes Service Account.

---

## Fase 1 — Testes na AWS (ECS/ECR)

### Arquitetura recomendada para testes

```
Internet
    │
  ALB (Application Load Balancer)
    │
  ┌─────────────────────────────────┐
  │  ECS Cluster (Fargate)          │
  │  ┌──────────┐  ┌─────────────┐ │
  │  │ngo-svc   │  │donation-svc │ │
  │  │:8081     │  │:8082        │ │
  │  └──────────┘  └─────────────┘ │
  │  ┌──────────┐                  │
  │  │volunteer │                  │
  │  │:8083     │                  │
  │  └──────────┘                  │
  └─────────────────────────────────┘
       │              │
      RDS          DynamoDB / SQS
  (PostgreSQL)
```

### Passo a passo

#### 1. Autenticar no ECR e fazer push das imagens

```bash
AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
AWS_REGION=us-east-1
ECR_BASE=$AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com

# Autenticar
aws ecr get-login-password --region $AWS_REGION \
  | docker login --username AWS --password-stdin $ECR_BASE

# Criar repositórios
for svc in ngo-service donation-service volunteer-service; do
  aws ecr create-repository --repository-name solidarytech/$svc --region $AWS_REGION
done

# Build e push
for svc in ngo-service donation-service volunteer-service; do
  docker build -t solidarytech/$svc ./$svc
  docker tag solidarytech/$svc $ECR_BASE/solidarytech/$svc:latest
  docker push $ECR_BASE/solidarytech/$svc:latest
done
```

#### 2. Escanear vulnerabilidades antes do push

```bash
# Habilitar scan automático no ECR
aws ecr put-image-scanning-configuration \
  --repository-name solidarytech/ngo-service \
  --image-scanning-configuration scanOnPush=true

# Verificar resultado do scan
aws ecr describe-image-scan-findings \
  --repository-name solidarytech/ngo-service \
  --image-id imageTag=latest
```

Ou localmente com [Trivy](https://trivy.dev/):
```bash
trivy image solidarytech/ngo-service:latest
```

#### 3. Criar Task Definitions no ECS

Exemplo de Task Definition para o `ngo-service` (JSON simplificado):

```json
{
  "family": "ngo-service",
  "networkMode": "awsvpc",
  "requiresCompatibilities": ["FARGATE"],
  "cpu": "256",
  "memory": "512",
  "executionRoleArn": "arn:aws:iam::ACCOUNT:role/ecsTaskExecutionRole",
  "taskRoleArn": "arn:aws:iam::ACCOUNT:role/ngo-service-task-role",
  "containerDefinitions": [
    {
      "name": "ngo-service",
      "image": "ACCOUNT.dkr.ecr.us-east-1.amazonaws.com/solidarytech/ngo-service:latest",
      "portMappings": [{"containerPort": 8081}],
      "environment": [
        {"name": "PORT", "value": "8081"}
      ],
      "secrets": [
        {
          "name": "DATABASE_URL",
          "valueFrom": "arn:aws:secretsmanager:us-east-1:ACCOUNT:secret:solidarytech/ngo/database-url"
        }
      ],
      "healthCheck": {
        "command": ["CMD-SHELL", "python -c \"import urllib.request; urllib.request.urlopen('http://localhost:8081/health')\""],
        "interval": 30,
        "timeout": 5,
        "retries": 3,
        "startPeriod": 10
      },
      "logConfiguration": {
        "logDriver": "awslogs",
        "options": {
          "awslogs-group": "/ecs/solidarytech/ngo-service",
          "awslogs-region": "us-east-1",
          "awslogs-stream-prefix": "ecs"
        }
      }
    }
  ]
}
```

> **Importante:** A `DATABASE_URL` é buscada do **AWS Secrets Manager** — nunca passada como plaintext. Repita o padrão de `secrets` para os demais serviços.

#### 4. Criar os Services no ECS

```bash
# Exemplo para ngo-service
aws ecs create-service \
  --cluster solidarytech-cluster \
  --service-name ngo-service \
  --task-definition ngo-service:1 \
  --desired-count 1 \
  --launch-type FARGATE \
  --network-configuration "awsvpcConfiguration={subnets=[subnet-xxx],securityGroups=[sg-xxx],assignPublicIp=DISABLED}" \
  --load-balancers "targetGroupArn=arn:aws:...,containerName=ngo-service,containerPort=8081"
```

### Teste rápido local antes do push

```bash
# Testar ngo-service localmente
docker build -t ngo-service ./ngo-service
docker run --rm -p 8081:8081 \
  -e DATABASE_URL="postgres://user:pass@host.docker.internal:5432/ngo_db" \
  ngo-service

curl http://localhost:8081/health
# Esperado: {"service":"ngo-service","status":"ok"}
```

---

## Fase 2 — Evolução para Kubernetes (EKS)

Quando o ambiente estiver validado no ECS, a migração para EKS segue esta estrutura:

### Estrutura de manifests

```
k8s/
├── namespace.yaml
├── ngo-service/
│   ├── deployment.yaml
│   ├── service.yaml
│   └── hpa.yaml
├── donation-service/
│   ├── deployment.yaml
│   ├── service.yaml
│   └── hpa.yaml
└── volunteer-service/
    ├── deployment.yaml
    ├── service.yaml
    └── hpa.yaml
```

### Exemplo de Deployment (ngo-service)

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: ngo-service
  namespace: solidarytech
  labels:
    app: ngo-service
    version: "1.0.0"
spec:
  replicas: 2
  selector:
    matchLabels:
      app: ngo-service
  template:
    metadata:
      labels:
        app: ngo-service
    spec:
      serviceAccountName: ngo-service-sa  # IRSA para permissões AWS
      securityContext:
        runAsNonRoot: true
        runAsUser: 1001
        fsGroup: 1001
      containers:
        - name: ngo-service
          image: ACCOUNT.dkr.ecr.us-east-1.amazonaws.com/solidarytech/ngo-service:latest
          ports:
            - containerPort: 8081
          env:
            - name: PORT
              value: "8081"
          envFrom:
            - secretRef:
                name: ngo-service-secrets  # DATABASE_URL via External Secrets Operator
          resources:
            requests:
              cpu: "100m"
              memory: "128Mi"
            limits:
              cpu: "500m"
              memory: "256Mi"
          livenessProbe:
            httpGet:
              path: /health
              port: 8081
            initialDelaySeconds: 10
            periodSeconds: 30
          readinessProbe:
            httpGet:
              path: /health
              port: 8081
            initialDelaySeconds: 5
            periodSeconds: 10
          securityContext:
            allowPrivilegeEscalation: false
            readOnlyRootFilesystem: true
            capabilities:
              drop: ["ALL"]
```

### Evolução da stack de deploy

```
Fase 1 (Testes)          Fase 2 (Produção)
─────────────────         ──────────────────────────────
ECS Fargate               EKS (Kubernetes)
ECR                       ECR (mesmo registry)
Secrets Manager           External Secrets Operator → Secrets Manager
ALB manual                AWS Load Balancer Controller
Manual deploy             GitOps com ArgoCD ou FluxCD
1 réplica                 HPA (Horizontal Pod Autoscaler)
Sem observabilidade       OpenTelemetry + Prometheus + Grafana
```

### Checklist de evolução

- [ ] Provisionar EKS via Terraform
- [ ] Configurar IRSA para cada serviço (substituindo ECS Task Roles)
- [ ] Instalar External Secrets Operator (integração com Secrets Manager)
- [ ] Configurar AWS Load Balancer Controller para Ingress
- [ ] Definir `resources.requests` e `resources.limits` (obrigatório para HPA)
- [ ] Configurar HPA para `donation-service` (componente crítico)
- [ ] Implementar `PodDisruptionBudget` para zero-downtime deploys
- [ ] Adicionar `NetworkPolicies` para micro-segmentação de rede
- [ ] Instrumentar com OpenTelemetry (traces, métricas, logs)
- [ ] Configurar ArgoCD para GitOps (sync automático do repositório)

---

## Comandos de Referência Rápida

### Build local de todos os serviços

```bash
docker build -t solidarytech/ngo-service:local       ./ngo-service
docker build -t solidarytech/donation-service:local  ./donation-service
docker build -t solidarytech/volunteer-service:local ./volunteer-service
```

### Verificar tamanho das imagens

```bash
docker images solidarytech/*
```

### Inspecionar usuário e layers

```bash
# Confirmar que não roda como root
docker run --rm solidarytech/ngo-service:local whoami
# Esperado: appuser

# Ver layers e tamanho de cada uma
docker history solidarytech/ngo-service:local
```

### Scan de vulnerabilidades com Trivy

```bash
# Instalar Trivy: https://trivy.dev/
trivy image --severity HIGH,CRITICAL solidarytech/ngo-service:local
trivy image --severity HIGH,CRITICAL solidarytech/donation-service:local
trivy image --severity HIGH,CRITICAL solidarytech/volunteer-service:local
```

### Tag versionada para produção

```bash
GIT_SHA=$(git rev-parse --short HEAD)
IMAGE_TAG="${GIT_SHA}-$(date +%Y%m%d)"

docker tag solidarytech/ngo-service:local \
  $ECR_BASE/solidarytech/ngo-service:$IMAGE_TAG

# Nunca usar apenas :latest em produção — sempre versionar com SHA do commit
```

---

> 💡 **Próximos passos sugeridos:** após validar os containers na AWS, evolua para adicionar um `docker-compose.yml` para desenvolvimento local completo (com PostgreSQL e LocalStack para simular DynamoDB/SQS), e em seguida configure o pipeline de CI/CD no GitHub Actions para automatizar o build, scan e push das imagens.
