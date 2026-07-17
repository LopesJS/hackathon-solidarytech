# Solidarytech Infra

Repositório de Infraestrutura como Código da plataforma **SolidaryTech**.


![Terraform](https://img.shields.io/badge/terraform-%235835CC.svg?style=for-the-badge&logo=terraform&logoColor=white)
![AWS](https://img.shields.io/badge/AWS-%23FF9900.svg?style=for-the-badge&logo=amazon-aws&logoColor=white)

---

## Estrutura do Repositório

```
solidarytech-infra/
├── terraform/
│   ├── modules/              ← Módulos reutilizáveis
│   │   ├── networking/       ← VPC, Subnets, Security Groups
│   │   ├── ecr/              ← Container Registry
│   │   ├── eks/              ← Kubernetes (AWS)
│   │   ├── ecs/              ← Fargate (alternativa / lab)
│   │   ├── rds/              ← PostgreSQL gerenciado
│   │   ├── dynamodb/         ← Tabelas NoSQL
│   │   └── sqs/              ← Filas de mensagens + DLQ
│   ├── environments/
│   │   ├── lab/              ← Desenvolvimento (ECS Spot, Single-AZ)
│   │   ├── aws-prod/         ← Produção AWS (EKS, Multi-AZ, DR)
│   │   ├── azure/            ← DR Multicloud (AKS warm standby)
│   │   └── gcp/              ← Terceira nuvem (GKE Autopilot)
│   └── global/
│       └── tags.tf           ← Política FinOps de tags obrigatórias
```

---

## 🚀 Quick Start

### Pré-requisitos

```bash
# Ferramentas necessárias
terraform --version   # >= 1.8.0
aws --version         # >= 2.0
kubectl version       # >= 1.28
kustomize version     # >= 5.0
argocd version        # >= 2.10
velero version        # >= 1.13
```

### 1. Clonar e configurar

```bash
git clone https://github.com/LopesJS/hackathon-solidarytech
cd hackathon-solidarytech

# Configurar credenciais AWS
aws configure --profile solidarytech
export AWS_PROFILE=solidarytech
```

### 2. Deploy em lab (desenvolvimento)

```bash
cd terraform/environments/lab

# Inicializar backend S3 (criar bucket antes se não existir)
terraform init

# Visualizar o que será criado
terraform plan -var="db_password=SenhaSuperSecreta123!"

# Aplicar
terraform apply -var="db_password=SenhaSuperSecreta123!"
```

### 3. Configurar kubectl para o cluster

```bash
# Após o apply, configurar kubeconfig
aws eks update-kubeconfig \
  --name solidarytech-lab \
  --region us-east-1

# Verificar nodes
kubectl get nodes

# Aplicar manifestos K8s
kubectl apply -k k8s/overlays/lab/
```

### 4. Deploy em produção (via GitHub Actions)

```bash
# Produção só é aplicada via GitHub Actions com approval manual.
# 1. Abra o workflow "Terraform Apply" no GitHub Actions
# 2. Selecione environment: aws-prod
# 3. Digite APLICAR para confirmar
# 4. Aguarde approval do team lead
```

---

## 🏷️ Política de Tags (FinOps)

Todos os recursos de nuvem possuem obrigatoriamente:

| Tag | Valor | Propósito |
|-----|-------|-----------|
| `Project` | `SolidaryTech` | Filtragem de custos por projeto |
| `Environment` | `lab` / `Production` | Separação por ambiente |
| `CostCenter` | `NGO-Core` / `NGO-Labs` | Alocação financeira |
| `ManagedBy` | `Terraform` | Governança IaC |
| `Owner` | `devops-team` | Responsabilidade |
| `Phase` | `Hackathon-Phase5` | Rastreabilidade do projeto |

Use sempre:
```hcl
tags = merge(var.tags, {
  Service = "donation-service"
  Layer   = "compute"
})
```

---

## 🏛️ Módulos Terraform

### `networking`
Cria VPC completa com subnets públicas/privadas, IGW, NAT Gateway e Security Groups pré-configurados.

```hcl
module "networking" {
  source = "../../modules/networking"
  environment          = "prod"
  vpc_cidr             = "10.0.0.0/16"
  availability_zones   = ["us-east-1a", "us-east-1b", "us-east-1c"]
  public_subnet_cidrs  = ["10.0.1.0/24", "10.0.2.0/24", "10.0.3.0/24"]
  private_subnet_cidrs = ["10.0.10.0/24", "10.0.11.0/24", "10.0.12.0/24"]
  tags                 = local.common_tags
}
```

### `eks`
EKS gerenciado com IRSA (IAM Roles for Service Accounts), suporte a Spot Instances e OIDC provider.

```hcl
module "eks" {
  source             = "../../modules/eks"
  kubernetes_version = "1.30"
  use_spot           = true       # 70% de economia em EC2
  node_min           = 2
  node_max           = 10
  tags               = local.common_tags
}
```

### `ecs`
ECS Fargate para ambientes lab — sem gerenciar nós, paga por task.

### `rds`
PostgreSQL com Enhanced Monitoring, Performance Insights e backup configurável. Multi-AZ automático em produção.

### `dynamodb`
Tabelas `volunteer-matches` e `donation-events` com GSIs, TTL e PITR habilitado.

### `sqs`
Fila principal de doações + DLQ + CloudWatch Alarm automático quando DLQ tem mensagens.

### `ecr`
Repositórios para os 3 serviços com lifecycle policy (10 imagens) e scan automático.

---

## ☁️ Environments

| Environment | Cloud | Kubernetes | DB | DR | Custo Estimado |
|-------------|-------|-----------|----|----|----------------|
| `lab` | AWS | ECS Fargate Spot | RDS Single-AZ | — | ~$30/mês |
| `aws-prod` | AWS | EKS (Spot+OD) | RDS Multi-AZ | Velero | ~$205/mês |
| `azure` | Azure | AKS | PostgreSQL Flex | Warm standby | ~$60/mês (DR ativo) |
| `gcp` | GCP | GKE Autopilot | Cloud SQL | Passivo | ~$40/mês (DR ativo) |

---

## 🔁 GitOps com ArgoCD

Os manifestos K8s são gerenciados pelo ArgoCD com sync automático:

```bash
# Instalar ArgoCD no cluster
kubectl create namespace argocd
kubectl apply -n argocd \
  -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

# Aplicar o projeto e as applications
kubectl apply -f argocd/projects/
kubectl apply -f argocd/apps/

# Acompanhar sincronização
argocd app list
argocd app sync donation-service
```

---

## 🛡️ Disaster Recovery

### Velero — Backup do cluster

```bash
# Instalar Velero
velero install \
  --provider aws \
  --plugins velero/velero-plugin-for-aws:v1.7.0 \
  --bucket solidarytech-velero-backups-$(aws sts get-caller-identity --query Account --output text) \
  --backup-location-config region=us-east-1 \
  --secret-file ./credentials-velero

# Schedule diário 02:00 BRT
velero schedule create daily-solidarytech \
  --schedule="0 5 * * *" \
  --include-namespaces solidarytech \
  --ttl 720h0m0s

# Verificar backups
velero backup get

# Restore completo
velero restore create --from-backup <backup-name> \
  --include-namespaces solidarytech \
  --wait
```

### Ativação do ambiente Azure DR

```bash
# Levantar warm standby em 1 comando
cd terraform/environments/azure
terraform init
terraform apply -var="db_password=${DB_PASSWORD}" -auto-approve

# RTO estimado: 4 horas | RPO: 1 hora
```

---

## 🔒 Segurança

- **Secrets:** nunca em código — injetados via `TF_VAR_*` no CI/CD
- **tfsec:** scan automático em todo PR
- **Network Policies:** donation-service só aceita tráfego interno
- **Non-root containers:** todos os pods rodam com `runAsNonRoot: true`
- **Storage encryption:** RDS, DynamoDB e S3 com criptografia em repouso

---

## 📋 Secrets necessários no GitHub

| Secret | Descrição |
|--------|-----------|
| `AWS_ROLE_ARN` | Role para OIDC em lab |
| `AWS_ROLE_ARN_PROD` | Role para OIDC em produção |
| `AWS_ACCOUNT_ID` | ID da conta AWS |
| `DB_PASSWORD` | Senha do PostgreSQL |
| `ALARM_SNS_ARN` | ARN do SNS para alertas (prod) |

---

## 👥 Equipe

| Nome | RM | GitHub |
|------|----|--------|
| <!-- --> | <!-- --> | <!-- --> |

---

<div align="center">

**SolidaryTech · solidarytech-infra**
POSTECH · DCLT · Hackathon Fase 5

*Infraestrutura imutável, declarativa e resiliente para uma causa que importa.*

</div>
