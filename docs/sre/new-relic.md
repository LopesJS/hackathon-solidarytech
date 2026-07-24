# SolidaryTech — New Relic: 

### Validação de Logs, Queries NRQL e Dashboards SRE

> Troubleshooting de telemetria chegando no New Relic, construção das queries NRQL dos SLIs e criação do dashboard SRE com Golden Metrics para o `donation-service` (Hot Path).

---

## Índice

1. [Verificar se os dados estão chegando](#1-verificar-se-os-dados-estão-chegando)
2. [Queries NRQL — Diagnóstico rápido](#2-queries-nrql--diagnóstico-rápido)
3. [Queries NRQL — SLIs do donation-service](#3-queries-nrql--slis-do-donation-service)
4. [Queries NRQL — Golden Metrics dos 3 serviços](#4-queries-nrql--golden-metrics-dos-3-serviços)
5. [Montar o Dashboard SRE](#5-montar-o-dashboard-sre)
6. [Configurar Alertas](#6-configurar-alertas)
7. [Troubleshooting](#7-troubleshooting)

---

## 1. Verificar se os dados estão chegando

### 1.1 — APM Services (Traces)

1. Acesse **[one.newrelic.com](https://one.newrelic.com)**
2. Menu esquerdo → **APM & Services**
3. Deve ver os 3 serviços listados:
   - `ngo-service`
   - `donation-service`
   - `volunteer-service`

> Se os serviços não aparecerem após 5 minutos de tráfego, vá para a seção [Troubleshooting](#8-troubleshooting).

---

### 1.2 — Gerar tráfego para ter dados

Antes de verificar qualquer coisa no New Relic, deve gere tráfego real nos 3 serviços:

```bash
ALB=$(cd infra/terraform/environments/lab && terraform output -raw alb_dns_name)
echo "ALB: $ALB"
```

```bash
# Health checks (aparecem como transações no APM)
for i in $(seq 1 10); do
  curl -s "http://${ALB}/health" > /dev/null
  curl -s "http://${ALB}/ngos" > /dev/null
  curl -s "http://${ALB}/donations" > /dev/null
  curl -s "http://${ALB}/volunteers/1" > /dev/null
done
```

```bash
# Criar dados reais
curl -s -X POST "http://${ALB}/ngos" \
  -H "Content-Type: application/json" \
  -d '{"name":"ONG Teste NR","email":"nr@teste.org","cause":"Educação","city":"SP"}'

curl -s -X POST "http://${ALB}/donations" \
  -H "Content-Type: application/json" \
  -d '{"ngo_id":1,"amount":250.00,"donor_name":"Teste New Relic"}'

curl -s -X POST "http://${ALB}/volunteers" \
  -H "Content-Type: application/json" \
  -d '{"name":"Voluntário NR","email":"vol@nr.com","ngo_id":1}'

echo "Tráfego gerado. Aguarde 2 minutos e verifique o New Relic."
```
---

### 1.3 — Query de verificação inicial no Query Builder

**New Relic → Query your data (ícone de gráfico no menu)**

```sql
-- Verificar se algum dado chegou nos últimos 30 minutos
SELECT count(*) 
FROM Transaction 
WHERE appName IN ('ngo-service', 'donation-service', 'volunteer-service') 
SINCE 30 minutes ago 
FACET appName
```

**Resultado esperado:**

| appName | count |
|---|---|
| ngo-service | > 0 |
| donation-service | > 0 |
| volunteer-service | > 0 |

---

## 2. Queries NRQL — Diagnóstico rápido

Use estas queries no **Query Builder** para confirmar que a instrumentação OTel está funcionando.

### 2.1 — Ver todas as transações recentes

```sql
SELECT appName, name, duration, httpResponseCode
FROM Transaction
WHERE appName IN ('ngo-service', 'donation-service', 'volunteer-service')
SINCE 1 hour ago
LIMIT 50
```

### 2.2 — Verificar atributos OTel enviados

```sql
-- Confirma que os atributos de resource estão chegando
SELECT uniques(service.namespace), uniques(deployment.environment), uniques(appName)
FROM Transaction
WHERE appName IN ('ngo-service', 'donation-service', 'volunteer-service')
SINCE 1 hour ago
```

**Esperado:**
- `service.namespace` = `solidarytech`
- `deployment.environment` = `lab`

### 2.3 — Throughput por serviço (requisições/min)

```sql
SELECT rate(count(*), 1 minute) AS 'req/min'
FROM Transaction
WHERE appName IN ('ngo-service', 'donation-service', 'volunteer-service')
SINCE 1 hour ago
FACET appName
TIMESERIES 1 minute
```

### 2.4 — Erros recentes

```sql
SELECT appName, name, errorMessage, httpResponseCode, timestamp
FROM TransactionError
WHERE appName IN ('ngo-service', 'donation-service', 'volunteer-service')
SINCE 1 hour ago
LIMIT 20
```

### 2.5 — Verificar spans (traces distribuídos)

```sql
SELECT count(*)
FROM Span
WHERE service.name IN ('ngo-service', 'donation-service', 'volunteer-service')
SINCE 1 hour ago
FACET service.name
```

---

## 3. Queries NRQL — SLIs do `donation-service`

O `donation-service` é o **Hot Path** da plataforma. Os SLIs e SLOs definidos são:

| SLI | Definição | SLO |
|---|---|---|
| **Latência** | % de requisições `POST /donations` com duração < 500ms | 95% em janela de 28 dias |
| **Taxa de Erro** | % de requisições com HTTP status < 500 | 99,9% em janela de 28 dias |

### 3.1 — SLI Latência (janela de 28 dias — para o SLO oficial)

```sql
SELECT percentage(count(*), WHERE duration < 0.5) AS 'SLI Latência (%)'
FROM Transaction
WHERE appName = 'donation-service'
AND name LIKE '%donations%'
SINCE 28 days ago
```

### 3.2 — SLI Taxa de Erro (janela de 28 dias — para o SLO oficial)

```sql
SELECT percentage(count(*), WHERE httpResponseCode < 500) AS 'SLI Taxa de Sucesso (%)'
FROM Transaction
WHERE appName = 'donation-service'
AND name LIKE '%donations%'
SINCE 28 days ago
```

### 3.3 — SLI Latência em tempo real (últimas 24h — para o dashboard)

```sql
SELECT percentage(count(*), WHERE duration < 0.5) AS 'Latência SLI'
FROM Transaction
WHERE appName = 'donation-service'
SINCE 24 hours ago
TIMESERIES 30 minutes
```

### 3.4 — Error Budget consumido

```sql
-- Error Budget = 0,1% do total de requests no mês
-- Esta query mostra o % do budget já consumido

SELECT
  (1 - percentage(count(*), WHERE httpResponseCode < 500) / 100) * 100 AS 'Erro Real (%)',
  0.1 AS 'Budget Total (%)',
  ((1 - percentage(count(*), WHERE httpResponseCode < 500) / 100) * 100 / 0.1) * 100 AS 'Budget Consumido (%)'
FROM Transaction
WHERE appName = 'donation-service'
SINCE 28 days ago
```

### 3.5 — Latência percentílica do donation-service

```sql
SELECT
  percentile(duration, 50)  AS 'p50 (ms)',
  percentile(duration, 95)  AS 'p95 (ms)',
  percentile(duration, 99)  AS 'p99 (ms)'
FROM Transaction
WHERE appName = 'donation-service'
SINCE 24 hours ago
TIMESERIES 15 minutes
```

> **Referência de SLO:** p95 deve ser < 500ms. Se a linha p95 cruzar a marca de 0.5s no gráfico, o SLO está sendo violado.

---

## 4. Queries NRQL — Golden Metrics dos 3 serviços

As 4 Golden Metrics de SRE (Google SRE Book): **Latência, Tráfego, Erros e Saturação**.

### 4.1 — LATÊNCIA — p50/p95/p99 por serviço

```sql
SELECT
  percentile(duration, 50) AS 'p50',
  percentile(duration, 95) AS 'p95',
  percentile(duration, 99) AS 'p99'
FROM Transaction
WHERE appName IN ('ngo-service', 'donation-service', 'volunteer-service')
SINCE 1 hour ago
FACET appName
TIMESERIES 5 minutes
```

### 4.2 — TRÁFEGO — Requisições por minuto

```sql
SELECT rate(count(*), 1 minute) AS 'Requisições/min'
FROM Transaction
WHERE appName IN ('ngo-service', 'donation-service', 'volunteer-service')
SINCE 1 hour ago
FACET appName
TIMESERIES 1 minute
```

### 4.3 — ERROS — Taxa de erro por serviço

```sql
SELECT
  filter(count(*), WHERE httpResponseCode >= 500) AS 'Erros 5xx',
  filter(count(*), WHERE httpResponseCode >= 400 AND httpResponseCode < 500) AS 'Erros 4xx',
  count(*) AS 'Total',
  percentage(count(*), WHERE httpResponseCode >= 500) AS 'Taxa de Erro 5xx (%)'
FROM Transaction
WHERE appName IN ('ngo-service', 'donation-service', 'volunteer-service')
SINCE 1 hour ago
FACET appName
TIMESERIES 5 minutes
```

### 4.4 — SATURAÇÃO — CPU e Memória via ECS Container Insights

```sql
-- CPU utilização dos containers ECS
SELECT average(cpuUtilized) AS 'CPU (units)'
FROM EcsContainerSample
WHERE clusterName = 'solidarytech-lab'
SINCE 1 hour ago
FACET containerName
TIMESERIES 5 minutes
```

```sql
-- Memória utilizada
SELECT average(memoryUtilized) AS 'Memória (MB)'
FROM EcsContainerSample
WHERE clusterName = 'solidarytech-lab'
SINCE 1 hour ago
FACET containerName
TIMESERIES 5 minutes
```


```sql
SELECT average(`aws.ecs.CPUUtilization`) AS 'CPU %'
FROM Metric
WHERE `aws.ecs.ClusterName` = 'solidarytech-lab'
SINCE 1 hour ago
FACET `aws.ecs.ServiceName`
TIMESERIES 5 minutes
```

### 4.5 — Apdex por serviço (satisfação do usuário)

```sql
-- Apdex com threshold de 500ms (T=0.5)
-- Satisfeito: < 0.5s | Tolerável: 0.5–2.0s | Frustrado: > 2.0s
SELECT apdex(duration, t: 0.5) AS 'Apdex'
FROM Transaction
WHERE appName IN ('ngo-service', 'donation-service', 'volunteer-service')
SINCE 1 hour ago
FACET appName
TIMESERIES 5 minutes
```

### 4.6 — Top endpoints por latência

```sql
SELECT average(duration) AS 'Latência Média (s)', count(*) AS 'Calls'
FROM Transaction
WHERE appName IN ('ngo-service', 'donation-service', 'volunteer-service')
SINCE 1 hour ago
FACET appName, name
ORDER BY average(duration) DESC
LIMIT 10
```

### 4.7 — Valor total de doações processadas

```sql
-- Rastreia o volume financeiro via atributos customizados
-- (requer instrumentação adicional no donation-service para enviar o amount)
SELECT count(*) AS 'Doações Processadas'
FROM Transaction
WHERE appName = 'donation-service'
AND name LIKE '%POST%donations%'
SINCE 24 hours ago
TIMESERIES 1 hour
```

---

## 5. Montar o Dashboard SRE

### 5.1 — Criar o dashboard

1. **New Relic → Dashboards → + Create a dashboard**
2. Nome: **`SolidaryTech`**
3. Visibilidade: **FREE PLAN** — Não é possível compartilhar o link público.
4. Clique em **Create**

### 5.2 — Widgets


---

#### SEÇÃO 1: SLO Status (linha do topo — visão executiva)

**Widget 1 — SLO Latência (Gauge/Billboard)**
```sql
SELECT percentage(count(*), WHERE duration < 0.5) AS 'SLO Latência'
FROM Transaction
WHERE appName = 'donation-service'
AND name LIKE '%donations%'
SINCE 28 days ago
```
- Tipo: **Billboard**
- Threshold verde: ≥ 95 | amarelo: ≥ 90 | vermelho: < 90

**Widget 2 — SLO Taxa de Sucesso (Gauge/Billboard)**
```sql
SELECT percentage(count(*), WHERE httpResponseCode < 500) AS 'SLO Sucesso'
FROM Transaction
WHERE appName = 'donation-service'
SINCE 28 days ago
```
- Tipo: **Billboard**
- Threshold verde: ≥ 99.9 | amarelo: ≥ 99 | vermelho: < 99

**Widget 3 — Error Budget Restante (Billboard)**
```sql
SELECT (0.1 - ((1 - percentage(count(*), WHERE httpResponseCode < 500) / 100) * 100)) AS 'Budget Restante (%)'
FROM Transaction
WHERE appName = 'donation-service'
SINCE 28 days ago
```
- Tipo: **Billboard**
- Threshold verde: > 0.05 | amarelo: > 0 | vermelho: ≤ 0

---

#### SEÇÃO 2: Golden Metrics em tempo real

**Widget 4 — Latência p50/p95/p99 (Line Chart)**
```sql
SELECT
  percentile(duration, 50) AS 'p50',
  percentile(duration, 95) AS 'p95',
  percentile(duration, 99) AS 'p99'
FROM Transaction
WHERE appName = 'donation-service'
SINCE 3 hours ago
TIMESERIES 5 minutes
```
- Tipo: **Line**

**Widget 5 — Tráfego — Req/min por serviço (Area Chart)**
```sql
SELECT rate(count(*), 1 minute) AS 'req/min'
FROM Transaction
WHERE appName IN ('ngo-service', 'donation-service', 'volunteer-service')
SINCE 3 hours ago
FACET appName
TIMESERIES 1 minute
```
- Tipo: **Area**

**Widget 6 — Taxa de Erro 5xx (Line Chart)**
```sql
SELECT percentage(count(*), WHERE httpResponseCode >= 500) AS 'Erro 5xx (%)'
FROM Transaction
WHERE appName IN ('ngo-service', 'donation-service', 'volunteer-service')
SINCE 3 hours ago
FACET appName
TIMESERIES 5 minutes
```
- Tipo: **Line**
- Marcar linha de referência em 0.1%

**Widget 7 — Saturação CPU ECS (Line Chart)**
```sql
SELECT average(`aws.ecs.CPUUtilization`) AS 'CPU %'
FROM Metric
WHERE `aws.ecs.ClusterName` = 'solidarytech-lab'
SINCE 3 hours ago
FACET `aws.ecs.ServiceName`
TIMESERIES 5 minutes
```
- Tipo: **Line**

---

#### SEÇÃO 3: Análise de erros e detalhes

**Widget 8 — Erros recentes (Table)**
```sql
SELECT timestamp, appName, name, errorMessage, httpResponseCode
FROM TransactionError
WHERE appName IN ('ngo-service', 'donation-service', 'volunteer-service')
SINCE 3 hours ago
LIMIT 20
```
- Tipo: **Table**

**Widget 9 — Top endpoints por latência (Bar Chart)**
```sql
SELECT average(duration) AS 'Latência Média (s)'
FROM Transaction
WHERE appName IN ('ngo-service', 'donation-service', 'volunteer-service')
SINCE 3 hours ago
FACET appName, name
LIMIT 10
```
- Tipo: **Bar**

**Widget 10 — Apdex (Gauge)**
```sql
SELECT apdex(duration, t: 0.5) AS 'Apdex'
FROM Transaction
WHERE appName = 'donation-service'
SINCE 3 hours ago
TIMESERIES 5 minutes
```
- Tipo: **Line** com threshold em 0.9

---

## 6. Configurar Alertas

### 6.1 — Criar Alert Policy

**New Relic → Alerts → Alert Policies → New alert policy**

- Nome: `SolidaryTech — SRE Alerts`
- Notification preference: **By condition and policy**

### 6.2 — Condição 1: SLO de Latência violado

**+ New alert condition → NRQL**

```sql
SELECT percentage(count(*), WHERE duration < 0.5)
FROM Transaction
WHERE appName = 'donation-service'
AND name LIKE '%donations%'
SINCE 5 minutes ago
```

- Threshold: `Static`
- Critical quando valor **cair abaixo de** `95` por `5 minutos`
- Nome: `donation-service — SLO Latência violado`

### 6.3 — Condição 2: Taxa de Erro acima do budget

```sql
SELECT percentage(count(*), WHERE httpResponseCode >= 500)
FROM Transaction
WHERE appName = 'donation-service'
SINCE 5 minutes ago
```

- Threshold: `Static`
- Critical quando valor **subir acima de** `0.1` por `5 minutos`
- Warning quando **acima de** `0.05` por `5 minutos`
- Nome: `donation-service — Error Budget burn rate alto`

### 6.4 — Condição 3: Serviço sem dados (ausência de sinal)

```sql
SELECT count(*)
FROM Transaction
WHERE appName IN ('ngo-service', 'donation-service', 'volunteer-service')
FACET appName
```

- Threshold: `Loss of signal`
- Sinalizar ausência após `5 minutos` sem dados
- Nome: `SolidaryTech — Serviço sem dados`

### 6.5 — Configurar notificação por e-mail

**Alerts → Notification Channels → + New notification channel**
- Tipo: **Email**
- E-mail: seu e-mail
- Associar à policy `SolidaryTech — SRE Alerts`

---


## 7. Troubleshooting

### Serviços não aparecem no APM

**Verificar se as variáveis OTel estão na task definition:**

```bash
aws ecs describe-task-definition \
  --task-definition solidarytech-lab-ngo-service \
  --query 'taskDefinition.containerDefinitions[0].environment' \
  --output table
```

Deve conter: `OTEL_EXPORTER_OTLP_ENDPOINT`, `OTEL_EXPORTER_OTLP_HEADERS`, `OTEL_SERVICE_NAME`.

**Verificar logs do container**

```bash
aws logs tail /ecs/solidarytech/lab/ngo-service --since 15m --follow
```

Procure por linhas como:
```
opentelemetry.sdk - INFO - Tracing enabled
```
Se aparecer `Connection refused` ou `Failed to export`, a `OTEL_EXPORTER_OTLP_HEADERS` está errada (license key inválida).

---

### Spans chegam mas APM não mostra serviço

O New Relic leva até **5 minutos** para criar a entidade do serviço na primeira vez. Se após 10 minutos de tráfego ainda não aparecer:

1. Vá em **New Relic → All Entities** e busque por `ngo-service`
2. Se aparecer como entidade mas não no APM, clique nela e verifique o tipo — pode ter sido registrado como `Service (OpenTelemetry)` em vez de `APM`
3. Query alternativa no Query Builder:

```sql
SELECT count(*) FROM Span 
WHERE service.name IN ('ngo-service', 'donation-service', 'volunteer-service')
SINCE 30 minutes ago FACET service.name
```

---

### Dados aparecem no Query Builder mas não no dashboard

- Verifique se o **Account ID** do dashboard é o mesmo da sua conta
- Abra cada widget e clique em **Edit** → **Run** para confirmar que a query retorna dados
- Se usar `EcsContainerSample` e não retornar dados, substitua pela query de `Metric` com `aws.ecs.*`

---

### License key incorreta

```bash
# Verificar qual key está configurada na task definition
aws ecs describe-task-definition \
  --task-definition solidarytech-lab-ngo-service \
  --query 'taskDefinition.containerDefinitions[0].environment[?name==`OTEL_EXPORTER_OTLP_HEADERS`].value' \
  --output text
```

A saída deve ser `api-key=INGEST-...`. Se estiver vazia ou com valor errado, re-aplique o Terraform:

```bash
export TF_VAR_newrelic_license_key='SUA_LICENSE_KEY_CORRETA'
export TF_VAR_db_password='SUA_SENHA'
cd infra/terraform/environments/lab
terraform apply -target=module.ecs -auto-approve
```

