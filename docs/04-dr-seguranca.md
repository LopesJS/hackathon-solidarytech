# 4. Multicloud, Segurança e Disaster Recovery (DR)

> Documentação da estratégia de segurança em profundidade, plano de continuidade de negócios e disaster recovery da plataforma SolidaryTech, com evidências dos controles já implementados via Infrastructure as Code.

---

## Filosofia de Segurança

A SolidaryTech opera sob quatro princípios de segurança que orientam toda a arquitetura:

1. **Defense in Depth** — múltiplas camadas de proteção (rede, IAM, criptografia, secrets)
2. **Least Privilege** — cada serviço acessa apenas o que precisa
3. **Encryption Everywhere** — dados em repouso e em trânsito sempre cifrados
4. **Everything as Code** — nenhuma configuração manual, tudo versionado no Git

Nenhum recurso da plataforma foi criado via console AWS. Toda mudança de infraestrutura passa por revisão de código, pipeline de CI com scans de segurança e aprovação antes de chegar ao ambiente.

---

## Segurança em Profundidade

### Camada 1 — Rede

| Controle | Implementação |
|---|---|
| Isolamento em VPC dedicada | `aws_vpc.main` — CIDR `10.10.0.0/16` (lab) / `10.0.0.0/16` (prod) |
| Subnets privadas para workloads | Tasks ECS rodam em subnets **sem rota direta para a internet** |
| Egress via NAT Gateway | Único ponto de saída controlado — permite auditoria |
| Security Groups por tier | `alb_sg` → `app_sg` → `rds_sg` (whitelist explícita entre camadas) |
| ALB como único ingress | Portas 80/443 abertas ao mundo apenas no ALB, nunca nas tasks |

**Evidência (Terraform):** `infra/terraform/modules/networking/main.tf`

### Camada 2 — Identidade e Acesso (IAM)

| Controle | Implementação |
|---|---|
| Task Role dedicada por ambiente | `data.aws_iam_role.lab_role` — usa LabRole (Vocareum) ou role customizada em prod |
| Sem credenciais estáticas em containers | Todo acesso AWS via IAM Role — sem `AWS_ACCESS_KEY_ID` no código |
| Autenticação de pipeline via OIDC (prod) | GitHub Actions assume IAM Role diretamente em `aws-prod` |
| Session tokens em lab (Vocareum) | Credenciais temporárias renováveis a cada 4h |

### Camada 3 — Criptografia

| Recurso | Em Repouso | Em Trânsito |
|---|---|---|
| **RDS PostgreSQL** | ✅ `storage_encrypted = true` (AES-256) | ✅ TLS obrigatório via `sslmode=require` na `DATABASE_URL` |
| **DynamoDB** | ✅ Server-Side Encryption padrão AWS | ✅ HTTPS obrigatório (SDK boto3) |
| **SQS** | ✅ `kms_master_key_id` configurado | ✅ TLS obrigatório (endpoint HTTPS) |
| **ECR** | ✅ `encryption_type = "AES256"` | ✅ TLS obrigatório no registry |
| **CloudWatch Logs** | ✅ Criptografia server-side AWS-managed | ✅ TLS obrigatório |
| **Telemetria OTel → New Relic** | N/A | ✅ gRPC sobre TLS (porta 4317) |

**Evidência:** todos os módulos Terraform em `infra/terraform/modules/*` declaram criptografia explicitamente.

### Camada 4 — Secrets

| Segredo | Onde vive | Como é injetado |
|---|---|---|
| Senha do RDS | GitHub Secret `DB_PASSWORD` | Via `TF_VAR_db_password` no pipeline Terraform |
| License key do New Relic | GitHub Secret `NEW_RELIC_LICENSE_KEY` | Via `TF_VAR_newrelic_license_key` |
| Credenciais AWS temporárias | GitHub Secrets (Vocareum) | Via `aws-actions/configure-aws-credentials` |
| String de conexão do banco | Montada no Terraform | Injetada como env var na task definition ECS |

**Princípio aplicado:** nenhum secret é commitado no repositório. O `.gitignore` bloqueia `.env`, `*.tfvars`, `credentials`, e verificamos com scan de segredos em cada PR via `TruffleHog` no pipeline.

### Camada 5 — DevSecOps no Pipeline

Cada push aciona 3 scans de segurança **antes** da imagem chegar ao ECR:

| Scan | Ferramenta | O que analisa |
|---|---|---|
| **SAST** | Semgrep (via GitHub Actions) | Vulnerabilidades no código Python/Go |
| **SCA + Container Scan** | Trivy | CVEs em dependências e camadas Docker |
| **IaC Scan** | tfsec (via `infra-terraform-plan.yml`) | Misconfigurações em recursos AWS |

Se qualquer scan encontrar vulnerabilidade `CRITICAL` sem patch, a pipeline falha e a imagem **não é publicada**.

---

## Plano de Continuidade de Negócios (PCN)

### Contexto e escopo

A SolidaryTech intermedia doações financeiras entre doadores e ONGs beneficiadas. Uma interrupção do serviço impacta diretamente:

- **Fluxo de doações não processadas** — perda de receita para as ONGs
- **Confiança dos doadores** — abandono da plataforma após tentativas malsucedidas
- **Compliance LGPD** — obrigação de disponibilidade dos dados dos usuários

O PCN a seguir cobre os cenários de indisponibilidade parcial ou total do ambiente principal (`us-east-1`).

### Objetivos de Recuperação (RTO/RPO)

Definidos por criticidade de dado, alinhados com a arquitetura já provisionada:

| Componente | RTO | RPO | Justificativa técnica |
|---|---|---|---|
| **RDS PostgreSQL** (doações + ONGs) | **4 horas** | **1 hora** | Backup automático diário + snapshots pontuais. Restaurar snapshot leva ~30-60 min; margem de 4h absorve validação e cutover. |
| **DynamoDB** (voluntários) | **1 hora** | **5 minutos** | Point-in-time recovery habilitado permite restaurar para qualquer segundo dos últimos 35 dias. |
| **SQS** (fila de doações) | **15 minutos** | **0 minuto** | Mensagens são efêmeras (retenção 24h); DLQ preserva as que não puderam ser processadas. |
| **ECR** (imagens Docker) | **30 minutos** | **0 minuto** | Imagens versionadas por SHA no Git; rebuild do último tag `latest` a partir do pipeline em <10min. |
| **Aplicação (ECS Fargate)** | **30 minutos** | **0 minuto** | Task definitions no Git; `terraform apply` recria o cluster em outra região. |
| **Configuração de infraestrutura** | **1 hora** | **0 minuto** | Terraform state versionado no S3 com versionamento habilitado. |

### Business Impact Analysis (BIA)

| Cenário | Probabilidade | Impacto financeiro/mês estimado | Prioridade |
|---|---|---|---|
| Falha de uma AZ na `us-east-1` | Média | Baixo (Multi-AZ absorve em prod) | Alta |
| Falha completa da região `us-east-1` | Baixa | Alto (perda de doações durante RTO) | Alta |
| Erro humano — DROP TABLE em produção | Baixa | Alto (perda de dados até último backup) | Alta |
| Comprometimento de credencial AWS | Baixa | Muito Alto (dados vazados, custos elevados) | Crítica |
| Deploy quebrado em produção | Alta | Médio (Circuit Breaker limita janela) | Média |

### Papéis e responsabilidades

| Papel | Responsabilidade | Ferramenta |
|---|---|---|
| **On-call SRE** | Primeira resposta a alertas | New Relic Alerts + e-mail |
| **DevOps Lead** | Acionamento do PCN, comunicação a stakeholders | Slack / e-mail executivo |
| **Time de Aplicação** | Diagnóstico de bugs de código | APM traces + CloudWatch Logs |
| **Comitê Executivo** | Comunicação a ONGs parceiras em incidente crítico | E-mail formal |

### Procedimento de acionamento

```
Alerta crítico disparado (SLO violado por 15+ min OU perda total de sinal)
   │
   ▼
On-call SRE valida no APM que não é falso positivo
   │
   ▼
Se região us-east-1 impactada → aciona DevOps Lead
   │
   ▼
DevOps Lead avalia:
   ├── Impacto localizado → mitigar via rollback ECS
   ├── Impacto regional (1 AZ) → deixar Multi-AZ absorver
   └── Impacto regional total → acionar DR em us-west-2
   │
   ▼
Comitê Executivo é comunicado se DR ativado
   │
   ▼
Post-mortem em até 5 dias úteis
```

---

## Estratégia de DR — Backup Automatizado + Terraform Cross-Region

A SolidaryTech adota uma abordagem de DR em **duas camadas complementares** que aproveitam ao máximo os recursos já provisionados na infraestrutura.

### Camada 1 — Backup automatizado gerenciado pela AWS

Todo o estado persistente da plataforma já possui backup contínuo habilitado via Terraform.

#### RDS PostgreSQL — Backup automático + snapshots

**Configuração aplicada em `infra/terraform/modules/rds/main.tf`:**

```hcl
resource "aws_db_instance" "postgres" {
  storage_encrypted         = true
  backup_retention_period   = var.backup_retention_days  # 1 dia (lab) / 7 dias (prod)
  backup_window             = "03:00-04:00"              # UTC (madrugada BR)
  maintenance_window        = "sun:04:00-sun:05:00"
  copy_tags_to_snapshot     = true
  skip_final_snapshot       = var.skip_final_snapshot
  final_snapshot_identifier = "${var.project}-${var.environment}-final-snapshot"
  deletion_protection       = var.deletion_protection
}
```

**Como funciona:**
- Backup completo diário durante a janela `03:00-04:00 UTC`
- **Point-in-Time Recovery (PITR)** habilitado — permite restaurar para qualquer segundo dentro da janela de retenção
- Snapshot final obrigatório ao destruir o RDS em produção (evita perda acidental)
- Tags copiadas para o snapshot (rastreabilidade de custo mesmo em backup)

**Procedimento de recuperação:**
```bash
# 1. Identificar o snapshot mais recente
aws rds describe-db-snapshots \
  --db-instance-identifier solidarytech-prod-postgres \
  --snapshot-type automated \
  --query 'DBSnapshots[0].DBSnapshotIdentifier' --output text

# 2. Restaurar em nova instância
aws rds restore-db-instance-from-db-snapshot \
  --db-instance-identifier solidarytech-recovered \
  --db-snapshot-identifier <snapshot-id>

# 3. Atualizar Terraform state para apontar para a nova instância
# 4. Force new deployment do ECS
```

**Tempo real esperado:** 30-60 minutos para RDS `db.t3.micro` com 20GB.

#### DynamoDB — Point-in-Time Recovery habilitado

**Configuração aplicada em `infra/terraform/modules/dynamodb/main.tf`:**

```hcl
resource "aws_dynamodb_table" "volunteer_matches" {
  # ...
  point_in_time_recovery {
    enabled = true
  }
  deletion_protection_enabled = var.environment == "lab" ? false : true
}

resource "aws_dynamodb_table" "donation_events" {
  # mesma configuração
}
```

**Como funciona:**
- Restauração para **qualquer segundo dos últimos 35 dias**
- **Zero downtime** — restauração cria uma nova tabela, mantendo a original acessível
- `deletion_protection_enabled = true` em produção previne exclusão acidental

**Procedimento de recuperação:**
```bash
aws dynamodb restore-table-to-point-in-time \
  --source-table-name solidarytech-prod-volunteer-matches-v2 \
  --target-table-name solidarytech-prod-volunteer-matches-recovered \
  --restore-date-time 2026-07-25T14:30:00Z
```

**Tempo real esperado:** 15-30 minutos (depende do tamanho da tabela).

#### SQS — Dead Letter Queue

**Configuração aplicada em `infra/terraform/modules/sqs/main.tf`:**

```hcl
resource "aws_sqs_queue" "donations" {
  message_retention_seconds  = 86400   # 24 horas
  kms_master_key_id          = local.kms_key
  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.dlq.arn
    maxReceiveCount     = 3
  })
}

resource "aws_sqs_queue" "dlq" {
  message_retention_seconds = 1209600  # 14 dias
  kms_master_key_id         = local.kms_key
}
```

**Como funciona:**
- Toda mensagem que falha 3 vezes vai para a DLQ
- Retenção de 14 dias na DLQ dá tempo para investigar e reprocessar
- Criptografia KMS aplicada em ambas as filas
- Ao reprocessar uma mensagem da DLQ, ela retorna ao fluxo normal sem perda

#### Terraform State — versionamento no S3

**Configuração no backend do Terraform:**

```hcl
backend "s3" {
  bucket         = "solidarytech-tfstate"
  key            = "aws-prod/terraform.tfstate"
  region         = "us-east-1"
  encrypt        = true
  dynamodb_table = "solidarytech-tfstate-lock"
}
```

**Proteções:**
- Versionamento habilitado no bucket S3 (nenhuma alteração de state é destrutiva)
- Criptografia em repouso via S3 SSE
- Lock via DynamoDB previne aplicação concorrente
- Estado é a "fonte da verdade" — permite reconstruir toda infraestrutura em qualquer região

---

### Camada 2 — Infraestrutura Ativo-Passivo via Terraform (Warm Standby)

A modularização completa do Terraform em `infra/terraform/modules/*` permite **subir um ambiente espelho em qualquer região AWS** apenas trocando uma variável.

#### Evidência da modularização multi-região

**Estrutura atual:**
```
infra/terraform/
├── modules/            ← código reutilizável, sem lock-in de região
│   ├── networking/     (recebe var.aws_region, var.availability_zones)
│   ├── rds/            (recebe var.subnet_ids)
│   ├── dynamodb/       (recebe var.region)
│   ├── sqs/            (independente de região)
│   ├── ecr/            (regional, mas todos serviços podem apontar para outra)
│   ├── ecs/            (recebe var.aws_region, var.private_subnet_ids)
│   └── eks/            (para o cenário prod)
└── environments/
    ├── lab/            (us-east-1 — ambiente ativo)
    ├── aws-prod/       (us-east-1 — ambiente primário de produção)
    └── aws-prod-dr/    (us-west-2 — ambiente warm standby, mesmo código)
```

**Como levantar a região secundária:**

```bash
# 1. Copiar o environment de produção para uma nova pasta apontando para outra região
cp -r infra/terraform/environments/aws-prod \
      infra/terraform/environments/aws-prod-dr

# 2. Alterar apenas 2 variáveis:
# environments/aws-prod-dr/variables.tf
variable "aws_region" {
  default = "us-west-2"    # ← única mudança regional
}

# 3. Aplicar
cd infra/terraform/environments/aws-prod-dr
export TF_VAR_db_password='xxx'
export TF_VAR_newrelic_license_key='xxx'
terraform init
terraform apply -auto-approve
```

**Resultado:** todo o stack (VPC, ALB, ECS, RDS, DynamoDB, SQS, ECR) sobe em `us-west-2` em **~25 minutos** (RDS é o gargalo).

#### Replicação de dados entre regiões (em prod)

Recomendações para próxima iteração (não implementadas no lab por limitação de custo):

| Dado | Estratégia de replicação | Custo/mês estimado |
|---|---|---|
| **RDS PostgreSQL** | Cross-Region Read Replica | ~$15 |
| **DynamoDB** | Global Tables (multi-region ativo-ativo) | Baseado no uso |
| **ECR** | Cross-Region Replication policy | ~$1 |
| **S3 (Terraform state)** | Cross-Region Replication habilitada | ~$0,50 |

---

## Testes de DR

### O que é feito hoje

| Teste | Frequência | Como | Evidência |
|---|---|---|---|
| **Recriação completa via IaC** | A cada mudança em módulos | Pipeline `terraform-apply` no ambiente `lab` | GitHub Actions logs |
| **Rollback automático de deploy** | A cada deploy | `deployment_circuit_breaker` do ECS | Deploy events do ECS |
| **Restauração de RDS de snapshot** | Ao destruir/recriar lab | `terraform destroy` + `terraform apply` | Snapshots visíveis no console |
| **Reprocessamento de DLQ** | Manual, quando necessário | AWS Console → SQS → Start DLQ redrive | Contagem de mensagens processadas |

### Roadmap de testes (próxima iteração)

- [ ] Chaos engineering: matar 1 task ECS periodicamente e validar auto-recovery
- [ ] Gameday trimestral: simular perda regional e validar RTO/RPO reais
- [ ] Backup restoration drill: mensalmente, restaurar snapshot em ambiente isolado

---

## Compliance LGPD

A plataforma processa dados pessoais de doadores e voluntários. Controles aplicados:

| Requisito LGPD | Controle técnico |
|---|---|
| Art. 46 — Segurança dos dados | Criptografia em repouso e trânsito em todas as camadas |
| Art. 46 — Controle de acesso | IAM Roles com least privilege + auditoria via CloudTrail |
| Art. 48 — Comunicação de incidentes | Alertas SRE + fluxo ITSM documentado (ver `03-itsm-aiops.md`) |
| Art. 16 — Eliminação de dados | Procedimento manual + `deletion_protection` para evitar erros |
| Art. 37 — Registro de operações | CloudWatch Logs com retenção configurada |

---

## Evidências de Operação

- [x] Criptografia habilitada em todos os data stores (RDS, DynamoDB, SQS, ECR, S3)
- [x] IAM com least privilege — sem credenciais estáticas em containers
- [x] Backups automáticos ativos no RDS e DynamoDB (PITR)
- [x] Dead Letter Queue configurada para não perder mensagens
- [x] Terraform state versionado no S3 com lock via DynamoDB
- [x] Modularização multi-região validada — mesmo código sobe em qualquer região AWS
- [x] Circuit Breaker do ECS ativo (rollback automático em deploy quebrado)
- [x] Scans de segurança no pipeline (Semgrep, Trivy, tfsec, TruffleHog)
- [x] RTO/RPO definidos por componente com base em capacidades reais

**Prints de evidência:**

![RDS — Backup automático habilitado](./dr/img/rds-backup-config.png)
![DynamoDB — Point-in-Time Recovery](./dr/img/dynamodb-pitr.png)
![Snapshots do RDS disponíveis](./dr/img/rds-snapshots.png)
![Estrutura Terraform multi-região](./dr/img/terraform-multi-region.png)

---

## Referências

- [AWS Well-Architected Framework — Reliability Pillar](https://docs.aws.amazon.com/wellarchitected/latest/reliability-pillar/welcome.html)
- [AWS RDS Automated Backups](https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/USER_WorkingWithAutomatedBackups.html)
- [DynamoDB Point-in-Time Recovery](https://docs.aws.amazon.com/amazondynamodb/latest/developerguide/PointInTimeRecovery.html)
- [Lei Geral de Proteção de Dados (LGPD) — Lei nº 13.709/2018](https://www.gov.br/anpd/pt-br)
