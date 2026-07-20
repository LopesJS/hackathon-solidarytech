# SolidaryTech Lab — Playbook de Operações

> Guia operacional do ambiente lab AWS — criação, destruição, economia de custos
> e troubleshooting. Baseado nos módulos **validados** em 19/07/2026.

---

## Índice

1. [Setup inicial](#1-setup-inicial)
2. [Subir o ambiente](#2-subir-o-ambiente-up)
3. [Destruir o ambiente](#3-destruir-o-ambiente-down)
4. [Pausar e retomar](#4-pausar-e-retomar-economia-de-custos)
5. [Verificar status](#5-verificar-status)
6. [Troubleshooting](#6-troubleshooting)
7. [Arquitetura do Lab](#7-arquitetura-do-lab)
8. [Referência rápida](#8-referência-rápida)

---

## 1. Setup inicial

### 1.1 Pré-requisitos

```bash
terraform version   # >= 1.6 (validado com 1.5.7)
aws --version       # >= 2.0
```

### 1.2 Credenciais AWS (Vocareum)

No terminal do Vocareum, copie as credenciais e exporte:

```bash
export AWS_ACCESS_KEY_ID="ASIA..."
export AWS_SECRET_ACCESS_KEY="..."
export AWS_SESSION_TOKEN="..."
export AWS_DEFAULT_REGION="us-east-1"

# Confirmar
aws sts get-caller-identity
```

> ⚠️ **Importante:** Credenciais do Vocareum expiram a cada sessão.
> Sempre re-exporte antes de rodar o script.

### 1.3 Senha do banco

```bash
export TF_VAR_db_password="SolidaryLab2024!"
# Mínimo 12 caracteres — validado automaticamente pelo Terraform
```

### 1.4 Posicionar o script

O `lab-manage.sh` deve estar na **raiz do projeto** (mesmo nível que a pasta `terraform/`):

```
solidarytech-infra/
├── lab-manage.sh          ← aqui
├── terraform/
│   ├── environments/lab/
│   └── modules/
└── ...
```

```bash
chmod +x lab-manage.sh
```

### 1.5 Terraform init (primeira vez)

```bash
cd terraform/environments/lab
terraform init
cd -
```

---

## 2. Subir o ambiente (`up`)

### Comando

```bash
./lab-manage.sh up
```

### O que acontece (sequência automática)

```
STEP 1A — Networking (~3 min)
  ✓ VPC 10.10.0.0/16
  ✓ 2 subnets públicas (10.10.1.0/24, 10.10.2.0/24)
  ✓ 2 subnets privadas (10.10.10.0/24, 10.10.11.0/24)
  ✓ Internet Gateway
  ✓ NAT Gateway + Elastic IP
  ✓ Route Tables
  ✓ Security Groups: ALB / App / RDS

STEP 1B — ECR (~1 min)
  ✓ solidarytech/ngo-service
  ✓ solidarytech/donation-service
  ✓ solidarytech/volunteer-service

STEP 2 — SQS + DynamoDB (~2 min)
  ✓ Fila: solidarytech-lab-donations
  ✓ Fila: solidarytech-lab-donations-dlq
  ✓ Fila: solidarytech-lab-volunteer-notifications
  ✓ Tabela: solidarytech-lab-volunteer-matches
  ✓ Tabela: solidarytech-lab-donation-events

STEP 3 — RDS PostgreSQL (~8-10 min)
  ✓ db.t3.micro / postgres16 / Single-AZ
  ✓ Storage: gp3 20GB (expandível até 50GB)
  ✓ Criptografia em repouso habilitada
  ✓ Aguarda status "available" automaticamente

STEP 4 — ECS Fargate Spot (~2 min)
  ✓ Cluster: solidarytech-lab
  ✓ Service: ngo-service      (1 task, 256 CPU / 512 MB)
  ✓ Service: donation-service (1 task, 512 CPU / 1024 MB)
  ✓ Service: volunteer-service (1 task, 256 CPU / 512 MB)
  ✓ CloudWatch Log Groups criados

STEP 5 — Verificação final
  ✓ Plan -detailed-exitcode (0 mudanças pendentes)
  ✓ Contagem de recursos tagueados
  ✓ Outputs exibidos
  ✓ Estimativa de custo
```

### Tempo total esperado

| Step | Tempo |
|------|-------|
| 1A Networking | ~3 min |
| 1B ECR | ~1 min |
| 2 SQS + DynamoDB | ~2 min |
| 3 RDS | **~8-10 min** |
| 4 ECS | ~2 min |
| **Total** | **~16-18 min** |

### Saída esperada ao final

```
━━━ Outputs da infraestrutura
  vpc_id: vpc-0abc123...
  ecs_cluster_name: solidarytech-lab
  ecr_repository_urls: ngo-service=123.dkr.ecr.us-east-1.amazonaws.com/solidarytech/ngo-service, ...
  donations_queue_url: https://sqs.us-east-1.amazonaws.com/486.../solidarytech-lab-donations
  volunteer_table_name: solidarytech-lab-volunteer-matches
  rds_endpoint: (sensitive — ver console ou terraform output -raw rds_endpoint)

━━━ Estimativa de custo
  NAT Gateway     ~$32.00/mês
  RDS PostgreSQL  ~$12.00/mês
  ECS Fargate     ~$ 2.00/mês
  TOTAL           ~$46.50/mês
```

---

## 3. Destruir o ambiente (`down`)

### Comando

```bash
./lab-manage.sh down
```

O script pede confirmação digitando `DESTRUIR`:

```
[WARN]  Esta operação irá DESTRUIR toda a infraestrutura do lab.
[WARN]  Recursos: VPC, ECS, RDS, DynamoDB, SQS, ECR
Digite DESTRUIR para confirmar: DESTRUIR
```

### Ordem de destruição

O Terraform resolve as dependências automaticamente e destrói na ordem inversa:

```
ECS Services → ECS Tasks → ECS Cluster
RDS Instance → RDS Subnet Group → RDS Parameter Group
NAT Gateway → Elastic IP
Subnets → Route Tables → Internet Gateway → VPC
SQS Queues
DynamoDB Tables
ECR Repositories
CloudWatch Log Groups
```

### Tempo esperado

~10-15 minutos (RDS demora ~5 min para terminar).

### Verificar que limpou tudo

```bash
./lab-manage.sh status
# Todos os recursos devem aparecer como "não encontrado"
```

---

## 4. Pausar e retomar (economia de custos)

O NAT Gateway custa **~$32/mês** — mais de 60% do custo total do lab.
Quando não estiver usando, pause-o.

### Pausar (fim do dia / semana)

```bash
./lab-manage.sh pause
```

O que acontece:
- Destrói o NAT Gateway e o Elastic IP
- Mantém **tudo mais**: RDS, ECS, DynamoDB, SQS, ECR, VPC
- As ECS tasks param de conseguir fazer pull de imagens do ECR
- **Economia: ~$32/mês** (proporcional ao tempo pausado)

### Retomar (início do dia)

```bash
./lab-manage.sh resume
```

O que acontece:
- Recria o NAT Gateway (~2 min)
- Aguarda 60 segundos
- Força redeploy dos 3 serviços ECS automaticamente

### Economia calculada

| Cenário | Custo estimado |
|---------|---------------|
| Lab ligado 24/7 (30 dias) | ~$46.50/mês |
| Lab ligado 8h/dia útil (22 dias) | ~$20.00/mês |
| Lab ligado só quando usar (10h/semana) | ~$10.00/mês |

---

## 5. Verificar status

```bash
./lab-manage.sh status
```

Exibe em sequência:

```
━━━ 🌐 Networking
[tabela VPC]
[OK] NAT Gateway: available

━━━ 📦 ECR
[tabela repositórios]

━━━ 🐳 ECS Cluster
[tabela services com Desired/Running/Pending]

━━━ 🗄️  RDS
[JSON com status, endpoint, classe, criptografia]

━━━ 📨 SQS
[lista de filas]

━━━ ⚡ DynamoDB
[lista de tabelas]

━━━ 🏷️  Recursos tagueados (FinOps)
[INFO] Total de recursos com tag Project=SolidaryTech: 24
```

### Comandos manuais complementares

```bash
# Ver logs de um serviço ECS
LOG_GROUP="/ecs/solidarytech/lab/donation-service"
aws logs tail $LOG_GROUP --follow

# Ver tasks em execução
aws ecs list-tasks --cluster solidarytech-lab

# Ver endpoint do RDS
cd terraform/environments/lab
terraform output -raw rds_endpoint

# Contar recursos tagueados (evidência FinOps)
aws resourcegroupstaggingapi get-resources \
  --tag-filters Key=Project,Values=SolidaryTech \
  --query 'length(ResourceTagMappingList)'
```

---

## 6. Troubleshooting

### ❌ `var.environment` sendo pedido interativamente

**Causa:** arquivo `terraform/global/tags.tf` com declarações `variable {}`.

**Fix:**
```bash
# Verificar se o arquivo tem variáveis
grep "^variable" terraform/global/tags.tf

# Se tiver, sobrescrever com versão correta (só comentários):
cat > terraform/global/tags.tf << 'EOF'
# Política de tags — documentação apenas.
# Variáveis são definidas em cada environment/main.tf
