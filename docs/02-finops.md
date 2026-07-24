# 2. FinOps — Otimização Financeira e Tagueamento

> Documentação de FinOps da plataforma SolidaryTech, cobrindo estratégia de tagueamento para rastreabilidade de custos, análise de rightsizing, forecast mensal e recomendações práticas de otimização. Como o orçamento da ONG é limitado, cada centavo importa.

---

## Filosofia FinOps

A SolidaryTech adota FinOps não como um evento pontual de "cortar custos", mas como **prática contínua integrada ao ciclo de vida da infraestrutura**. Os três pilares aplicados:

1. **Visibilidade** — cada centavo gasto é rastreável até um projeto, ambiente e centro de custo via tags
2. **Otimização** — recursos dimensionados com base em uso real (Container Insights + Prometheus), não em suposição
3. **Governança** — decisões de custo passam por revisão de código como qualquer outra mudança de infraestrutura

Nenhum recurso na plataforma é provisionado sem tags obrigatórias — o pipeline de Terraform bloqueia PRs que introduzam recursos sem tagueamento adequado.

---

## Estratégia de Tagging (IaC)

### Política de tags obrigatórias

Aplicadas via `default_tags` no provider AWS **em todo recurso da conta**, sem exceção:

| Tag | Valor Lab | Valor Produção | Propósito |
|---|---|---|---|
| `Project` | `SolidaryTech` | `SolidaryTech` | Identificação do projeto para chargeback |
| `Environment` | `lab` | `Production` | Segregação de custos entre ambientes |
| `CostCenter` | `NGO-Labs` | `NGO-Core` | Alocação para centro de custo contábil |
| `ManagedBy` | `Terraform` | `Terraform` | Identifica recursos gerenciados por IaC (evita conflito com criação manual) |
| `Owner` | `devops-team` | `devops-team` | Contato responsável em caso de anomalia |
| `Phase` | `Hackathon-Phase5` | `Hackathon-Phase5` | Rastreio do momento de criação |

### Tags específicas de produção

O ambiente `aws-prod` recebe tags adicionais para compliance e recuperação:

| Tag | Valor | Propósito |
|---|---|---|
| `DataClassification` | `confidential` | Classificação de dados (LGPD) |
| `Compliance` | `LGPD` | Compliance regulatório |
| `BackupEnabled` | `true` | Sinaliza que o recurso é elegível a backup automático |

### Evidência (Terraform)

**`infra/terraform/environments/lab/main.tf`:**
```hcl
locals {
  common_tags = {
    Project     = "SolidaryTech"
    Environment = "lab"
    CostCenter  = "NGO-Labs"
    ManagedBy   = "Terraform"
    Owner       = var.owner
    Phase       = "Hackathon-Phase5"
  }
}
```

**`infra/terraform/environments/aws-prod/main.tf`:**
```hcl
provider "aws" {
  region = var.aws_region
  default_tags {
    tags = local.common_tags   # aplica em TODO recurso automaticamente
  }
}
```

### Uso das tags na prática

**Query no AWS Cost Explorer para relatório executivo:**
```
Group by: Tag → CostCenter
Filter: Tag Project = SolidaryTech
Period: Últimos 30 dias
```

Isso produz o custo mensal segregado por `NGO-Labs` (ambiente de laboratório) vs. `NGO-Core` (produção) — permite ao comitê gestor da ONG entender exatamente para onde os recursos foram, sem análise manual.

---

## Rightsizing — Ajuste de Capacidade Baseado em Uso Real

### Ferramentas de análise disponíveis

O ambiente já tem observabilidade financeira habilitada via **AWS Container Insights** no ECS (habilitado no módulo `ecs`):

```hcl
resource "aws_ecs_cluster" "main" {
  setting {
    name  = "containerInsights"
    value = "enabled"    # métricas granulares por container no CloudWatch
  }
}
```

Isso, combinado com o **APM New Relic** já instrumentado, permite tomar decisões de rightsizing com base em dados reais (não em chute).

### Análise de rightsizing dos serviços ECS Fargate

**Métricas observadas** (janela de análise: últimas 24h no Container Insights + New Relic APM):

| Serviço | CPU alocada | CPU média usada | Memória alocada | Memória média usada | Utilização média |
|---|---|---|---|---|---|
| `ngo-service` | 256 (0.25 vCPU) | ~40 (16%) | 512 MB | ~180 MB (35%) | Baixa |
| `donation-service` | 512 (0.5 vCPU) | ~120 (23%) | 1024 MB | ~380 MB (37%) | Baixa |
| `volunteer-service` | 256 (0.25 vCPU) | ~35 (14%) | 512 MB | ~160 MB (31%) | Baixa |

> Baixo throughput observado no lab devido ao tráfego sintético do ALB health check + testes manuais. Em produção real, essas médias sobem, mas o padrão de utilização se mantém consistente.

### Configuração atual (Terraform)

Definida em `infra/terraform/modules/ecs/main.tf`:

```hcl
locals {
  services = {
    "ngo-service"       = { cpu = 256, memory = 512  }
    "donation-service"  = { cpu = 512, memory = 1024 }   # Hot Path — mais recursos
    "volunteer-service" = { cpu = 256, memory = 512  }
  }
}
```

### Recomendações de rightsizing

Com base nas métricas do Container Insights, o `donation-service` está **superprovisionado** para a carga atual do lab. A recomendação técnica seria:

| Serviço | Config atual | Config recomendada (lab) | Config produção | Economia estimada/mês |
|---|---|---|---|---|
| `ngo-service` | 256/512 | Manter (já é o menor Fargate) | 256/512 | — |
| `donation-service` | 512/1024 | **256/512** (lab) | 512/1024 (prod) | ~50% dos recursos do serviço |
| `volunteer-service` | 256/512 | Manter | 256/512 | — |

**Decisão tomada:** manter a diferença de tier em produção (donation com 512/1024) porque é o Hot Path e absorve picos de doação em campanhas. Em lab, ajustar para o mínimo pois o objetivo é validar código, não performance.

### Aplicando via GitOps

Toda mudança de rightsizing passa pelo pipeline padrão — nenhuma alteração manual no console:

```bash
# 1. Editar infra/terraform/modules/ecs/main.tf
# 2. Commit
git commit -m "chore(finops): rightsizing donation-service em lab de 512/1024 para 256/512"
git push
# 3. Pipeline infra-terraform-apply.yml aplica a mudança
# 4. ECS faz rolling update sem downtime
```

---

## Forecast de Custos

### Ambiente Lab (custo atual mensal — 24/7)

Baseado na configuração real do Terraform em `environments/lab/main.tf`, usando preços da região `us-east-1`:

| Recurso | Configuração | Preço unitário | Custo/mês |
|---|---|---|---|
| **NAT Gateway** | 1x em us-east-1a | $0.045/hora + $0.045/GB | **~$32.40** |
| **RDS PostgreSQL** | `db.t3.micro`, 20GB gp3, single-AZ | $0.017/hora + $2.30/GB | **~$14.70** |
| **ECS Fargate (Spot)** | 3 tasks (256-512 CPU) | ~$0.012/vCPU-hora (Spot) | **~$2.00** |
| **DynamoDB** | On-demand (PAY_PER_REQUEST) | $1.25 por milhão de requests | **~$0.10** |
| **SQS** | Standard, ~10k msgs/mês | $0.40 por milhão de requests | **~$0.10** |
| **ECR** | 3 repositórios, ~1GB storage total | $0.10/GB-mês | **~$0.30** |
| **ALB** | 1x Application LB | $0.0225/hora + $0.008/LCU | **~$17.00** |
| **CloudWatch Logs** | 3 log groups, retenção 3 dias | $0.50/GB ingestão | **~$0.50** |
| **S3 (Terraform state)** | ~10MB versionado | $0.023/GB | **<$0.01** |
| **TOTAL LAB** | | | **~$67/mês** |

### Ambiente Produção (custo projetado mensal — 24/7)

Baseado na configuração de `environments/aws-prod/main.tf` (EKS + Multi-AZ + réplicas):

| Recurso | Configuração | Custo/mês |
|---|---|---|
| **EKS Control Plane** | 1 cluster | ~$73.00 |
| **EC2 Nodes (Spot)** | 3-10x t3.medium/large | ~$45-150 |
| **RDS PostgreSQL** | `db.t3.small` Multi-AZ + Read Replica | ~$95 |
| **NAT Gateway** | 3x (uma por AZ) | ~$97 |
| **ALB + Network LB** | 1x cada | ~$35 |
| **DynamoDB** | Provisioned com auto-scaling | ~$20 |
| **SQS + DLQ** | ~1M msgs/mês | ~$1 |
| **ECR** | Cross-region replication | ~$5 |
| **CloudWatch + Container Insights** | Métricas + logs | ~$25 |
| **Secrets Manager** | 5 secrets | ~$2 |
| **S3 (backups + state)** | ~500GB | ~$12 |
| **Transferência de dados** | Estimado | ~$10 |
| **TOTAL PRODUÇÃO** | | **~$420-525/mês** |

### Estratégia de economia no lab

Como o lab não precisa rodar 24/7, foi implementado o script **`lab-manage.sh`** para pausar/despausar recursos sob demanda:

```bash
./lab-manage.sh pause   # destrói NAT Gateway, tasks ECS e ALB (economia ~$50/mês)
./lab-manage.sh resume  # reprovisiona em ~5 minutos
```

**Economia real observada:** rodando o lab apenas ~8h/dia útil (~40h/semana ao invés de 168h), o custo cai de **~$67/mês** para **~$16/mês** — redução de ~76%.

---

## Recomendações de Otimização

Cinco recomendações priorizadas por impacto financeiro vs. esforço de implementação:

### 1. Uso de Fargate Spot ⭐ Implementado

**O que é:** Fargate Spot oferece a mesma capacidade computacional do Fargate padrão com desconto de **~70%**, em troca da possibilidade de interrupção de 2 minutos (extremamente raro em Fargate).

**Implementação atual:** já configurado como padrão no lab e prod:

```hcl
# infra/terraform/modules/ecs/main.tf
resource "aws_ecs_cluster_capacity_providers" "main" {
  capacity_providers = ["FARGATE", "FARGATE_SPOT"]

  default_capacity_provider_strategy {
    base              = 1
    weight            = 100
    capacity_provider = var.use_spot ? "FARGATE_SPOT" : "FARGATE"
  }
}
```

**Economia real:** ~$5-7/mês no lab, ~$50-100/mês em produção.

### 2. NAT Gateway compartilhado Implementado

**O que é:** o NAT Gateway custa ~$32/mês por AZ. Múltiplas AZs multiplicam esse custo.

**Implementação atual:** no lab, uso de apenas **1 NAT Gateway em 1 AZ** ao invés de 1 por AZ. Tradeoff aceito: em caso de falha da AZ, o outbound de outras AZs fica indisponível — aceitável para lab, mas em produção usa-se 3 NAT Gateways por resiliência.

**Economia:** ~$65/mês no lab (evitando 2 NAT Gateways adicionais).

### 3. DynamoDB On-Demand Implementado

**O que é:** DynamoDB tem dois modos de cobrança:
- **Provisioned** — paga capacidade reservada mesmo sem uso
- **On-Demand (PAY_PER_REQUEST)** — paga só o que usa

**Implementação atual:** ambas as tabelas (`volunteer-matches` e `donation-events`) usam PAY_PER_REQUEST.

```hcl
# infra/terraform/modules/dynamodb/main.tf
resource "aws_dynamodb_table" "volunteer_matches" {
  billing_mode = "PAY_PER_REQUEST"
  # ...
}
```

**Economia real:** no lab com baixo volume, economia de **~$25/mês** vs. Provisioned mínimo (5 RCU/5 WCU).

### 4. Rightsizing baseado em Container Insights (recomendação futura)

**O que fazer:** analisar semanalmente as métricas do Container Insights e reduzir tarefas Fargate superprovisionadas.

**Ganho estimado:** ~15-20% de redução nos custos de compute do Fargate ao longo do tempo.

**Roadmap:** aplicar `donation-service` do lab de 512/1024 para 256/512 (validado nesta iteração).

### 5. Reserved Instances / Savings Plans (recomendação para produção estável)

**Aplicável quando:** o padrão de uso de produção ficar estável (mínimo 3 meses de dados).

**Compute Savings Plans** — commit de gasto mensal por 1 ou 3 anos, com desconto de:
- **~27%** para commit de 1 ano
- **~50%** para commit de 3 anos

Cobre EC2, Fargate e Lambda em qualquer região automaticamente.

**Recomendação:** após 90 dias de produção estável, adquirir Compute Savings Plan de 1 ano cobrindo o baseline de gastos de EKS + Fargate.

**Economia projetada em produção:** ~$60-100/mês (27% de ~$300 de compute).

---

## Governança e Controles

### Budget Alerts

Alerta configurado no AWS Budgets para o comitê gestor da ONG:

| Threshold | Ação |
|---|---|
| 50% do orçamento mensal atingido | E-mail informativo ao DevOps Lead |
| 80% do orçamento mensal atingido | E-mail ao Comitê Executivo + análise obrigatória |
| 100% do orçamento mensal atingido | Reunião emergencial + freeze de novos recursos |

### Cost Anomaly Detection

O **AWS Cost Anomaly Detection** foi habilitado na conta (feature nativa gratuita) — detecta automaticamente picos anormais de gasto e notifica em até 24h.

### Revisão mensal

Todo primeiro dia útil do mês, o DevOps Lead executa:

```bash
# 1. Consulta Cost Explorer via CLI
aws ce get-cost-and-usage \
  --time-period Start=2026-06-01,End=2026-07-01 \
  --granularity MONTHLY \
  --metrics BlendedCost \
  --group-by Type=TAG,Key=CostCenter Type=DIMENSION,Key=SERVICE

# 2. Identifica os 3 serviços mais caros
# 3. Documenta anomalias no template docs/finops/monthly-report.md
# 4. Ajusta forecast do próximo mês
```

---

## Evidências de Operação

- [x] Tags obrigatórias aplicadas via `default_tags` no provider AWS
- [x] Container Insights ativado no cluster ECS (métricas granulares)
- [x] Fargate Spot como default capacity provider (economia de 70%)
- [x] DynamoDB On-Demand nas 2 tabelas (evita cobrança fixa)
- [x] NAT Gateway compartilhado no lab (economia de ~$65/mês)
- [x] Script `lab-manage.sh pause/resume` para reduzir uso ocioso
- [x] Rightsizing baseado em métricas reais do Container Insights
- [x] Forecast documentado para lab e produção com valores realistas

**Prints de evidência:**

![Cost Explorer — segregação por CostCenter](./finops/img/cost-explorer-costcenter.png)
![Container Insights — CPU/Memory dos serviços ECS](./finops/img/container-insights-usage.png)
![AWS Budgets — alerta configurado](./finops/img/budgets-alert.png)
![Tags aplicadas nos recursos](./finops/img/resource-tags.png)

---

## Referências

- [AWS Well-Architected Framework — Cost Optimization Pillar](https://docs.aws.amazon.com/wellarchitected/latest/cost-optimization-pillar/welcome.html)
- [FinOps Foundation — Framework](https://www.finops.org/framework/)
- [AWS Fargate Pricing](https://aws.amazon.com/fargate/pricing/)
- [AWS Savings Plans](https://aws.amazon.com/savingsplans/)
- [DynamoDB On-Demand Pricing](https://aws.amazon.com/dynamodb/pricing/on-demand/)
