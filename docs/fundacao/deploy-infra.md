# SolidaryTech — Guia de Deploy na AWS com Terraform (Lab)

> Documentação completa para provisionar toda a infraestrutura da plataforma SolidaryTech na AWS usando Terraform, publicar as imagens Docker no ECR e subir os 3 microsserviços no ECS Fargate.

---

## Índice

1. [Arquitetura](#arquitetura)
2. [Pré-requisitos](#pré-requisitos)
3. [Estrutura do repositório](#estrutura-do-repositório)
4. [Passo 1 — Configurar credenciais AWS](#passo-1--configurar-credenciais-aws)
5. [Passo 2 — Criar o backend do Terraform](#passo-2--criar-o-backend-do-terraform)
6. [Passo 3 — Inicializar o Terraform](#passo-3--inicializar-o-terraform)
7. [Passo 4 — Planejar a infraestrutura](#passo-4--planejar-a-infraestrutura)
8. [Passo 5 — Aplicar a infraestrutura](#passo-5--aplicar-a-infraestrutura)
9. [Passo 6 — Publicar imagens no ECR](#passo-6--publicar-imagens-no-ecr)
10. [Passo 7 — Executar migrations do banco](#passo-7--executar-migrations-do-banco)
11. [Passo 8 — Validar os serviços](#passo-8--validar-os-serviços)
12. [Recursos criados](#recursos-criados)
13. [Custos estimados](#custos-estimados)
14. [Destruir o ambiente](#destruir-o-ambiente)
15. [Troubleshooting](#troubleshooting)

---

## Arquitetura

```
Internet
    │
    ▼
┌─────────────────────────────────────────────────────────────┐
│  Application Load Balancer (público)                        │
│  /ngos*  → ngo-service:8081                                 │
│  /donations* → donation-service:8082                        │
│  /volunteers* → volunteer-service:8083                      │
└──────────────────────┬──────────────────────────────────────┘
                       │ (subnets privadas)
           ┌───────────┼───────────┐
           ▼           ▼           ▼
    ┌──────────┐ ┌──────────┐ ┌──────────────┐
    │ngo-svc   │ │donation  │ │volunteer-svc │
    │Fargate   │ │Fargate   │ │Fargate       │
    │256CPU    │ │256CPU    │ │256CPU        │
    │512MB     │ │512MB     │ │512MB         │
    └────┬─────┘ └────┬─────┘ └──────┬───────┘
         │            │              │
         ▼            ▼              ▼
    ┌─────────┐  ┌─────────┐  ┌──────────────┐
    │RDS      │  │RDS      │  │DynamoDB      │
    │ngo_db   │  │donation │  │Volunteers    │
    │         │  │_db + SQS│  │(PAY_PER_REQ) │
    └─────────┘  └─────────┘  └──────────────┘
```

### Componentes provisionados pelo Terraform

| Módulo | Recursos criados |
|---|---|
| `networking` | VPC, 2 subnets públicas, 2 subnets privadas, IGW, NAT Gateway, Route Tables, 3 Security Groups |
| `ecr` | 3 repositórios ECR com scan automático e lifecycle policy |
| `rds` | Instância PostgreSQL 15 (db.t3.micro), subnet group, parameter group, enhanced monitoring |
| `dynamodb` | Tabela `SolidaryTechVolunteers` com GSI por ngo_id, PITR habilitado |
| `sqs` | Fila `solidary-donations` + Dead Letter Queue |
| `secrets` | 3 secrets no AWS Secrets Manager (DATABASE_URLs + RDS password) |
| `ecs` | Cluster ECS, ALB, 3 Target Groups, 3 Listener Rules, 3 Task Definitions, 3 Services, IAM Roles |

---

## Pré-requisitos

### Ferramentas necessárias

| Ferramenta | Versão mínima | Instalação |
|---|---|---|
| AWS CLI | 2.x | https://aws.amazon.com/cli/ |
| Terraform | 1.7.0 | https://www.terraform.io/downloads |
| Docker | 24.x | https://docs.docker.com/get-docker/ |
| Git | qualquer | https://git-scm.com |

**Verificar instalações:**
```bash
aws --version          # aws-cli/2.x.x
terraform version      # Terraform v1.7.x
docker --version       # Docker version 24.x
git --version          # git version 2.x
```

### Permissões IAM necessárias

O usuário ou role AWS utilizado precisa ter permissões para criar todos os recursos. Em ambiente de lab, a policy `AdministratorAccess` é a mais simples. Em produção, use uma policy customizada com as permissões mínimas necessárias:

- `ec2:*` (VPC, subnets, security groups, NAT, IGW)
- `elasticloadbalancing:*` (ALB, target groups, listeners)
- `ecs:*` (cluster, tasks, services)
- `ecr:*` (repositórios)
- `rds:*` (instância PostgreSQL)
- `dynamodb:*` (tabelas)
- `sqs:*` (filas)
- `secretsmanager:*` (secrets)
- `iam:*` (roles e policies para ECS)
- `logs:*` (CloudWatch log groups)
- `s3:*` (bucket do terraform state)

---

## Estrutura do repositório

```
hackathon-solidarytech/infra
├── .github
├── .gitignore
├── terraform/
│   ├── global/
│   │   └── tags.tf                  ← política de tags FinOps
│   ├── modules/
│   │   ├── networking/              ← VPC, subnets, SGs
│   │   │   ├── main.tf
│   │   │   ├── variables.tf
│   │   │   └── outputs.tf
│   │   ├── ecr/                     ← repositórios de imagens
│   │   │   ├── main.tf
│   │   │   ├── variables.tf
│   │   │   └── outputs.tf
│   │   ├── rds/                     ← PostgreSQL
│   │   │   ├── main.tf
│   │   │   ├── variables.tf
│   │   │   └── outputs.tf
│   │   ├── dynamodb/                ← tabela de voluntários
│   │   │   ├── main.tf
│   │   │   ├── variables.tf
│   │   │   └── outputs.tf
│   │   ├── sqs/                     ← fila de doações + DLQ
│   │   │   ├── main.tf
│   │   │   ├── variables.tf
│   │   │   └── outputs.tf
│   │   ├── secrets/                 ← AWS Secrets Manager
│   │   │   ├── main.tf
│   │   │   ├── variables.tf
│   │   │   └── outputs.tf
│   │   └── ecs/                     ← cluster, ALB, tasks, services
│   │       ├── main.tf
│   │       ├── variables.tf
│   │       └── outputs.tf
│   └── environments/
│       ├── lab/                     ← ambiente de laboratório
│       │   ├── main.tf              ← orquestra todos os módulos
│       │   ├── variables.tf
│       │   ├── outputs.tf
│       │   ├── terraform.tfvars     ← valores do lab (não commitar)
│       │   ├── bootstrap.sh         ← cria o backend S3+DynamoDB
│       │   ├── deploy.sh            ← build + push + ECS deploy
│       │   └── migrate.sh           ← guia de migrations SQL
│       └── aws-prod/                ← ambiente de produção (próxima fase)
```

---

## Passo 1 — Configurar credenciais AWS

### Opção A — AWS CLI configure (mais simples para lab)

```bash
aws configure
# AWS Access Key ID: AKIA...
# AWS Secret Access Key: ...
# Default region name: us-east-1
# Default output format: json
```

### Opção B — Variáveis de ambiente

```bash
export AWS_ACCESS_KEY_ID="AKIA..."
export AWS_SECRET_ACCESS_KEY="..."
export AWS_DEFAULT_REGION="us-east-1"
```

### Verificar que as credenciais funcionam

```bash
aws sts get-caller-identity
```

Saída esperada:
```json
{
  "UserId": "AIDA...",
  "Account": "123456789012",
  "Arn": "arn:aws:iam::123456789012:user/seu-usuario"
}
```

---

## Passo 2 — Criar o backend do Terraform

O backend remoto armazena o `terraform.tfstate` no S3 e usa DynamoDB para impedir que dois `apply` rodem ao mesmo tempo.

Execute o script de bootstrap **uma única vez**:

```bash
cd terraform/environments/lab
chmod +x bootstrap.sh
./bootstrap.sh us-east-1
```

O script cria:
- Bucket S3 `solidarytech-tfstate-lab` com versionamento e criptografia
- Tabela DynamoDB `solidarytech-tfstate-lock` para state locking

> ⚠️ **Atenção:** se quiser usar um nome de bucket diferente, edite o `bootstrap.sh` **e** a configuração `backend "s3"` no `main.tf` antes de rodar o `terraform init`.

---

## Passo 3 — Inicializar o Terraform

```bash
cd terraform/environments/lab
terraform init
```

Saída esperada:
```
Initializing the backend...
Successfully configured the backend "s3"!

Initializing modules...
- module.networking
- module.ecr
- module.rds
- module.dynamodb
- module.sqs
- module.secrets
- module.ecs

Terraform has been successfully initialized!
```

---

## Passo 4 — Planejar a infraestrutura

O `plan` mostra tudo que será criado **sem criar nada**. Sempre revise antes do `apply`.

```bash
terraform plan -out=tfplan
```

Saída esperada (resumo):
```
Plan: 47 to add, 0 to change, 0 to destroy.
```

Recursos principais que serão criados:
- `aws_vpc.main`
- `aws_subnet.public[0,1]` e `aws_subnet.private[0,1]`
- `aws_nat_gateway.main[0]`
- `aws_ecr_repository.services["ngo-service"]` (+ donation + volunteer)
- `aws_db_instance.main`
- `aws_dynamodb_table.volunteers`
- `aws_sqs_queue.donations` + `donations_dlq`
- `aws_secretsmanager_secret.*` (3 secrets)
- `aws_ecs_cluster.main`
- `aws_lb.main` (ALB)
- `aws_ecs_task_definition.*` (3 task definitions)
- `aws_ecs_service.*` (3 services)

---

## Passo 5 — Aplicar a infraestrutura

```bash
terraform apply tfplan
```

> ⏱️ **Tempo estimado:** 15–25 minutos (o RDS é o mais lento — ~10 min para provisionamento).

Ao finalizar, o Terraform exibe os outputs:

```
Outputs:

alb_dns_name        = "solidarytech-lab-alb-1234567890.us-east-1.elb.amazonaws.com"
ecr_urls            = {
  "donation-service"  = "123456789012.dkr.ecr.us-east-1.amazonaws.com/solidarytech/donation-service"
  "ngo-service"       = "123456789012.dkr.ecr.us-east-1.amazonaws.com/solidarytech/ngo-service"
  "volunteer-service" = "123456789012.dkr.ecr.us-east-1.amazonaws.com/solidarytech/volunteer-service"
}
ecs_cluster_name    = "solidarytech-lab"
dynamodb_table_name = "SolidaryTechVolunteers"
sqs_queue_url       = "https://sqs.us-east-1.amazonaws.com/123456789012/solidary-donations"
```

Salve o `alb_dns_name` — você vai usar para testar no Passo 8.

---

## Passo 6 — Publicar imagens no ECR

As imagens Docker precisam estar no ECR antes dos containers subirem no ECS.

### Opção A — Script automatizado

```bash
# Ainda dentro de terraform/environments/lab/
chmod +x deploy.sh
./deploy.sh
```

### Opção B — Comandos manuais

```bash
# Variáveis
REGION="us-east-1"
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
ECR_BASE="$ACCOUNT_ID.dkr.ecr.$REGION.amazonaws.com"

# Autenticar no ECR
aws ecr get-login-password --region $REGION \
  | docker login --username AWS --password-stdin $ECR_BASE

# Build e push de cada serviço (execute a partir da raiz do repositório de código)
for svc in ngo-service donation-service volunteer-service; do
  docker build -t solidarytech/$svc:latest ./$svc
  docker tag solidarytech/$svc:latest $ECR_BASE/solidarytech/$svc:latest
  docker push $ECR_BASE/solidarytech/$svc:latest
  echo "✓ $svc publicado"
done

# Forçar novo deploy no ECS (para usar as novas imagens)
CLUSTER=$(terraform output -raw ecs_cluster_name)
for svc in ngo-service donation-service volunteer-service; do
  aws ecs update-service --cluster $CLUSTER --service $svc \
    --force-new-deployment --region $REGION --no-cli-pager
done
```

---

## Passo 7 — Executar migrations do banco

As tabelas do PostgreSQL precisam ser criadas antes dos serviços ficarem saudáveis.

### Via AWS RDS Query Editor (console web — mais simples para lab)

1. Acesse o **AWS Console → RDS → Query Editor**
2. Conecte à instância `solidarytech-lab-postgres`
   - Database username: `solidary`
   - Database password: recupere do Secrets Manager:
     ```bash
     aws secretsmanager get-secret-value \
       --secret-id "solidarytech/lab/rds/master-password" \
       --query SecretString --output text
     ```
3. Execute os SQLs:

```sql
-- Criar os bancos
CREATE DATABASE ngo_db;
CREATE DATABASE donation_db;
```

4. Troque para o banco `ngo_db` e execute:

```sql
CREATE TABLE IF NOT EXISTS ngos (
  id         SERIAL PRIMARY KEY,
  name       VARCHAR(150) NOT NULL,
  email      VARCHAR(100) UNIQUE NOT NULL,
  cause      VARCHAR(100) NOT NULL,
  city       VARCHAR(100) NOT NULL,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

INSERT INTO ngos (name, email, cause, city) VALUES
  ('Anjos de Patas', 'contato@anjosdepatas.org', 'Proteção Animal', 'Osasco'),
  ('Educa Mais', 'info@educamais.org', 'Educação', 'São Paulo');
```

5. Troque para `donation_db` e execute:

```sql
CREATE TABLE IF NOT EXISTS donations (
  id         SERIAL PRIMARY KEY,
  ngo_id     INT NOT NULL,
  amount     NUMERIC(10, 2) NOT NULL,
  donor_name VARCHAR(100) NOT NULL,
  status     VARCHAR(20) NOT NULL,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);
```

### Verificar que as tasks estão healthy após as migrations

```bash
aws ecs describe-services \
  --cluster solidarytech-lab \
  --services ngo-service donation-service volunteer-service \
  --query "services[*].{Name:serviceName, Running:runningCount, Desired:desiredCount}" \
  --output table
```

---

## Passo 8 — Validar os serviços

Substitua `<ALB_DNS>` pelo valor do output `alb_dns_name`.

```bash
ALB="<ALB_DNS>"

# Health checks
curl http://$ALB/health
# {"status":"ok","service":"ngo-service"}

# Listar ONGs (seed já inserido nas migrations)
curl http://$ALB/ngos

# Criar uma ONG
curl -X POST http://$ALB/ngos \
  -H "Content-Type: application/json" \
  -d '{"name":"Instituto Test","email":"test@ong.org","cause":"Educação","city":"Curitiba"}'

# Registrar uma doação
curl -X POST http://$ALB/donations \
  -H "Content-Type: application/json" \
  -d '{"ngo_id":1,"amount":100.00,"donor_name":"Fulano da Silva"}'

# Cadastrar um voluntário
curl -X POST http://$ALB/volunteers \
  -H "Content-Type: application/json" \
  -d '{"name":"Maria Costa","email":"maria@email.com","ngo_id":1}'

# Buscar voluntários de uma ONG
curl http://$ALB/volunteers/1
```

---

## Recursos criados

### Resumo completo

| Serviço AWS | Recurso | Qtd |
|---|---|---|
| VPC | VPC + subnets + IGW + NAT + RTs | 1 VPC, 4 subnets |
| EC2 | Security Groups | 3 |
| ECR | Repositórios de imagem | 3 |
| ECS | Cluster + Task Definitions + Services | 1 cluster, 3 TDs, 3 services |
| ELB | ALB + Target Groups + Listener + Rules | 1 ALB, 3 TGs, 4 rules |
| RDS | Instância PostgreSQL 15 | 1 |
| DynamoDB | Tabela + GSI | 1 tabela |
| SQS | Fila principal + DLQ | 2 filas |
| Secrets Manager | Secrets | 3 |
| IAM | Roles + Policies | 4 roles, 6 policies |
| CloudWatch | Log Groups | 3 |

### Tags FinOps aplicadas a todos os recursos

```
Project     = "SolidaryTech"
Environment = "lab"
CostCenter  = "NGO-Core"
ManagedBy   = "Terraform"
Owner       = "devops"
```

---

## Custos estimados

| Recurso | Tipo | Custo/mês (estimado) |
|---|---|---|
| ECS Fargate | 3 tasks × 0.25 vCPU × 0.5 GB | ~$12 |
| RDS PostgreSQL | db.t3.micro, 20 GB gp3 | ~$15 |
| NAT Gateway | ~10 GB/mês de dados | ~$5 |
| ALB | ~10 LCUs | ~$18 |
| DynamoDB | PAY_PER_REQUEST, baixo volume | < $1 |
| SQS | < 1M requests/mês | < $1 |
| ECR | < 1 GB de storage | < $1 |
| CloudWatch Logs | 3 days retention | < $1 |
| Secrets Manager | 3 secrets | < $1 |
| **Total lab** | | **~$55/mês** |

> 💡 **Dica de economia:** destrua o ambiente quando não estiver usando:
> ```bash
> terraform destroy
> ```
> O NAT Gateway e o RDS são os maiores custos. Para economizar ainda mais, configure o `enable_nat_gateway = false` e use subnets públicas para as tasks no lab.

---

## Destruir o ambiente

```bash
cd terraform/environments/lab
terraform destroy
```

> ⚠️ **Atenção:** isso remove **todos** os recursos, incluindo dados do RDS e DynamoDB. Em produção, habilite `deletion_protection = true` no RDS.

Para destruir somente um módulo específico:
```bash
# Destruir apenas o ECS (mantém banco e rede)
terraform destroy -target=module.ecs
```

---

## Troubleshooting

### Tasks ECS ficam em PENDING

**Causa mais comum:** as imagens ainda não foram publicadas no ECR.

```bash
# Verificar se as imagens existem no ECR
aws ecr list-images --repository-name solidarytech/ngo-service

# Ver eventos do serviço ECS
aws ecs describe-services \
  --cluster solidarytech-lab \
  --services ngo-service \
  --query "services[0].events[:5]"
```

### Tasks ECS ficam em STOPPED

**Verificar logs do container:**

```bash
# Pegar o ARN da task que falhou
aws ecs list-tasks --cluster solidarytech-lab --service-name ngo-service

# Ver logs no CloudWatch
aws logs get-log-events \
  --log-group-name /ecs/solidarytech/lab/ngo-service \
  --log-stream-name ecs/ngo-service/<task-id>
```

### Health check do ALB falhando

**Verificar se as migrations foram executadas:**
```bash
# O ngo-service falha no health check se a tabela `ngos` não existir
# Execute as migrations do Passo 7 e force novo deploy:
aws ecs update-service \
  --cluster solidarytech-lab \
  --service ngo-service \
  --force-new-deployment
```

### Erro `ResourceNotFoundException` no DynamoDB

A tabela `SolidaryTechVolunteers` não foi criada. Verifique:
```bash
aws dynamodb list-tables --region us-east-1
# Se vazio, o módulo dynamodb não foi aplicado
terraform apply -target=module.dynamodb
```

### Erro de credenciais AWS no Terraform

```bash
# Verificar qual identidade está sendo usada
aws sts get-caller-identity

# Garantir que a região está configurada
export AWS_DEFAULT_REGION="us-east-1"
```

### `terraform apply` falha no backend S3

O bucket não existe. Execute o bootstrap primeiro:
```bash
./bootstrap.sh us-east-1
```

---

> **Próximo passo:** após validar o ambiente lab, a Semana 2 do cronograma cobre a migração para EKS com CI/CD automatizado via GitHub Actions e GitOps com ArgoCD. Consulte o `CRONOGRAMA.md` para o roadmap completo.
