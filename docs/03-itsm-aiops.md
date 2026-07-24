# 3. ITSM e AIOps — Gestão Preditiva de Incidentes

> Documentação da estratégia de gestão de incidentes (ITSM) e detecção preditiva via inteligência artificial (AIOps) da plataforma SolidaryTech. Complementa a documentação de [SRE](./01-sre.md) ao formalizar o **ciclo de vida do incidente**, papéis, responsabilidades e comunicação com stakeholders.

---

## Filosofia ITSM/AIOps

A plataforma SolidaryTech opera sob o princípio de que **incidentes devem ser previstos antes de afetarem o doador final**. Três pilares orientam a operação:

1. **Detecção preditiva** — anomalias comportamentais são detectadas antes do usuário perceber (AIOps sobre a stack OTel + New Relic já implementada)
2. **Ciclo de vida estruturado** — todo incidente segue um fluxo padronizado da detecção ao post-mortem, sem improviso
3. **Comunicação transparente** — as ONGs parceiras são informadas em incidentes críticos com linguagem executiva, não técnica

Este documento **não repete** a definição de SLOs, dashboards ou alertas, que já vivem em `01-sre.md`. Aqui foca-se em **como os incidentes são operados quando disparam**.

---

## Configuração de AIOps — New Relic Applied Intelligence

### O que é

O **New Relic Applied Intelligence (AI)** é o mecanismo nativo de detecção de anomalias da plataforma, ativado sobre os traces e métricas OTel já em produção. Diferente de alertas tradicionais baseados em threshold estático, o AIOps:

- **Aprende o padrão de comportamento** de cada serviço nas primeiras 2 semanas
- **Correlaciona automaticamente** múltiplos sinais (latência + erro + throughput + CPU) em um único "incidente"
- **Reduz alert fatigue** ao consolidar dezenas de alertas correlacionados em uma única notificação

### Funcionalidades ativadas

| Funcionalidade | Status | O que faz |
|---|---|---|
| **Anomaly Detection** | ✅ Ativado | Detecta desvios do comportamento normal em latência e taxa de erro sem threshold manual |
| **Correlation** | ✅ Ativado | Agrupa alertas relacionados em um único incidente |
| **Error Inbox** | ✅ Ativado | Deduplica erros idênticos e classifica por frequência |
| **Log Patterns** | ✅ Ativado | Detecta mensagens de log recorrentes vs. anomalias raras |
| **Golden Signals correlation** | ✅ Ativado | Correlaciona os 4 Golden Metrics (latência, tráfego, erros, saturação) automaticamente |

### Como o AIOps complementa os alertas NRQL

Os alertas NRQL configurados no SRE (`SolidaryTech — SRE Alerts`) detectam **violações conhecidas** de SLO. O AIOps detecta **problemas não previstos** — casos onde nenhum alerta manual foi criado, mas o comportamento saiu do baseline.

Exemplo prático:
- **Alerta NRQL manual:** dispara quando latência do `donation-service` passa de 300ms
- **AIOps:** dispararia se a latência subisse de 50ms para 200ms **sem cruzar o threshold de 300ms**, porque 200ms é anômalo em relação ao baseline histórico

Essa camada preditiva **antecipa incidentes em ~15-30 minutos** vs. alertas tradicionais, reduzindo o MTTR ainda mais.

### Evidência

**Print da tela de Applied Intelligence:**
![New Relic Applied Intelligence — Overview](./itsm/img/newrelic-ai-overview.png)

**Print de anomalia detectada:**
![Anomaly Detection — donation-service](./itsm/img/newrelic-anomaly-detection.png)

---

## Ciclo de Vida do Incidente

O ciclo de vida na SolidaryTech tem **6 fases** e é executado em **todos** os incidentes independente da severidade. A diferença entre severidades está no tempo e na profundidade de cada fase.

```
┌─────────────────────────────────────────────────────────────────┐
│                    CICLO DE VIDA DO INCIDENTE                    │
└─────────────────────────────────────────────────────────────────┘

  1. DETECÇÃO                       2. TRIAGEM
  ─────────────                     ─────────────
  Sinal disparado por:              On-call SRE avalia:
  • Alerta NRQL                     • É falso positivo?
  • AIOps anomaly                   • Qual severidade (P1/P2/P3)?
  • Reclamação de usuário           • Quem precisa ser acionado?
       │                                    │
       └──────────►     ◄──────────────────┘
                        │
                        ▼
  3. RESPOSTA (MITIGAÇÃO)           4. RESOLUÇÃO
  ─────────────────────             ─────────────
  Ações imediatas para              Correção definitiva:
  restabelecer o serviço:           • Deploy do fix
  • Rollback via ArgoCD/ECS         • Scaling permanente
  • Scale up de tasks               • Ajuste de config
  • Failover para DR                • Validação com métricas
       │                                    │
       └──────────►     ◄──────────────────┘
                        │
                        ▼
  5. POST-MORTEM                    6. COMUNICAÇÃO
  ─────────────                     ─────────────
  Documento blameless em 5 dias:    Stakeholders informados:
  • Timeline detalhada              • Doadores (se P1)
  • Causa raiz (5 whys)             • ONGs parceiras (se P1)
  • Impacto quantificado            • Comitê gestor (P1 e P2)
  • Ações corretivas                • Time interno (todos)
```

### Classificação de severidade

| Severidade | Definição | Exemplo | Tempo máximo de resposta |
|---|---|---|---|
| **P1 — Crítico** | Serviço indisponível OU perda de dados | `donation-service` retornando 5xx em 100% das requisições | **15 minutos** |
| **P2 — Alto** | Degradação significativa SEM perda de dados | Latência do POST /donations > 2s | **1 hora** |
| **P3 — Médio** | Impacto limitado ou parcial | 1 serviço secundário down (ex: `volunteer-service`) | **4 horas** |
| **P4 — Baixo** | Sem impacto ao usuário | Warning de deprecação de biblioteca | **1 dia útil** |

### Detalhamento das 6 fases

#### Fase 1 — Detecção

Três origens possíveis, em ordem de preferência:

| Origem | Latência de detecção | Confiança |
|---|---|---|
| **AIOps (New Relic AI)** | 1-5 min antes do threshold | Média-Alta |
| **Alerta NRQL (SRE Alerts Policy)** | 5-15 min após ocorrência | Alta |
| **Reclamação de usuário** | 30 min a horas | Alta (mas tardio) |

**Objetivo:** 90% dos incidentes P1/P2 detectados por AIOps ou alerta automático (sem depender do usuário).

#### Fase 2 — Triagem

Executada pelo on-call SRE em até 5 minutos após a detecção. Perguntas obrigatórias:

1. É falso positivo? (verificar no dashboard SRE)
2. Qual serviço afetado? (verificar traces no APM)
3. Qual a severidade? (aplicar matriz P1-P4 acima)
4. Preciso escalar? (aplicar matriz RACI abaixo)

**Ferramenta:** Dashboard SRE + APM traces do New Relic (já documentado em `01-sre.md`).

#### Fase 3 — Resposta / Mitigação

Ações **imediatas** para restabelecer serviço, mesmo que a causa raiz ainda não seja conhecida:

| Sintoma | Ação de mitigação |
|---|---|
| Deploy quebrado | `deployment_circuit_breaker` já reverte automaticamente (~3 min) |
| Task ECS travada | Force new deployment via CLI |
| Sobrecarga temporária | Scale up manual do `desired_count` no ECS |
| Falha regional | Ativar ambiente DR em `us-west-2` (ver `04-dr-seguranca.md`) |
| Fila SQS acumulando | Aumentar consumers ou reprocessar da DLQ |

#### Fase 4 — Resolução

Correção **definitiva** — deploy de código, ajuste de configuração, escalamento de capacidade permanente. Sempre validada por métricas antes de fechar o incidente:

- SLI de latência voltou > 95%?
- SLI de sucesso voltou > 99,9%?
- Alertas todos em estado `Resolved`?

#### Fase 5 — Post-Mortem

**Obrigatório** para todo incidente P1 e P2. Prazo máximo: **5 dias úteis** após resolução. Formato **blameless** (foca em processos, não em pessoas).

Template obrigatório em `docs/postmortems/YYYY-MM-DD-titulo.md`:

```markdown
# Post-Mortem — <título curto>

**Data:** <data do incidente>
**Duração:** <XX minutos>
**Severidade:** P<X>
**Impacto:** <quantitativo — Error Budget consumido, doações afetadas, etc.>

## Timeline
| Horário (UTC) | Evento |
|---|---|
| HH:MM | AIOps detectou anomalia |
| HH:MM | On-call acionado |
| HH:MM | Mitigação aplicada |
| HH:MM | Serviço restabelecido |

## Causa Raiz
Análise dos 5 Porquês.

## O que deu certo
- ...

## O que deu errado
- ...

## Ações corretivas
- [ ] <ação> — <responsável> — <prazo>
```

**Regra:** ações corretivas viram issues no GitHub com o label `postmortem` e são rastreadas até conclusão.

#### Fase 6 — Comunicação

Executada **em paralelo** às fases 3-5 (não sequencial). Público e mensagem variam por severidade:

| Público | P1 | P2 | P3 | P4 |
|---|---|---|---|---|
| Time DevOps interno | Imediato (Slack) | Imediato (Slack) | Diário standup | Weekly report |
| Comitê Gestor ONG | E-mail em ≤ 30 min | E-mail em ≤ 2h | Relatório mensal | Não comunicado |
| ONGs parceiras | E-mail em ≤ 1h | E-mail em ≤ 4h | Não comunicado | Não comunicado |
| Doadores finais | Status page + rede social | Status page | Não comunicado | Não comunicado |

---

## Matriz RACI de Resposta a Incidentes

Definição clara de papéis para cada fase, evitando ambiguidade em situações de estresse:

| Fase | On-call SRE | DevOps Lead | Time Aplicação | Comitê Gestor |
|---|---|---|---|---|
| **Detecção** | A / R | I | I | — |
| **Triagem** | A / R | C | I | — |
| **Mitigação** | R | A | C / R | — |
| **Resolução** | R | A | R | I |
| **Post-Mortem** | R | A | R | C |
| **Comunicação a stakeholders** | I | R | I | A |

**Legenda:**
- **R** — Responsible (executa)
- **A** — Accountable (responde)
- **C** — Consulted (é consultado)
- **I** — Informed (é informado)

---

## Runbook Operacional

Coletânea de procedimentos padronizados para os cenários mais frequentes. Cada runbook fica em `docs/runbooks/`.

### Runbook 1 — Deploy quebrado no ECS

```bash
# Sintoma: alertas de erro após novo deploy
# Verificação:
aws ecs describe-services --cluster solidarytech-lab \
  --services donation-service \
  --query 'services[0].{Deployments:deployments,Events:events[:5]}'

# Mitigação automática já ativa via deployment_circuit_breaker.
# Se rollback automático não bastar:
aws ecs update-service --cluster solidarytech-lab \
  --service donation-service \
  --task-definition solidarytech-lab-donation-service:<REVISAO_ANTERIOR> \
  --force-new-deployment
```

### Runbook 2 — Filas SQS acumulando

```bash
# Sintoma: alerta de DLQ com mensagens
# Verificação:
aws sqs get-queue-attributes \
  --queue-url $(terraform output -raw dlq_url) \
  --attribute-names ApproximateNumberOfMessages

# Reprocessamento manual da DLQ:
aws sqs start-message-move-task \
  --source-arn <dlq_arn> \
  --destination-arn <main_queue_arn>
```

### Runbook 3 — RDS com alta latência

```sql
-- Consulta queries lentas (Enhanced Monitoring)
SELECT query, calls, total_time / calls AS avg_ms
FROM pg_stat_statements
ORDER BY total_time DESC
LIMIT 10;

-- Se identificado query problemática, adicionar índice via migração.
-- Se saturação de conexões: aumentar max_connections no parameter group.
```

### Runbook 4 — Ativação do DR

Ver documento dedicado em [`04-dr-seguranca.md`](./04-dr-seguranca.md), seção *Procedimento de acionamento*.

---

## Redução de MTTR via ITSM/AIOps

O ciclo estruturado + AIOps compõem com a stack SRE já implementada para atingir a meta de **MTTR < 20 minutos** (ver detalhamento em `01-sre.md`):

| Etapa | Contribuição do ITSM/AIOps |
|---|---|
| **Detecção** | AIOps antecipa em 15-30min vs. alerta manual |
| **Triagem** | Matriz de severidade elimina indecisão do on-call |
| **Mitigação** | Runbooks pré-escritos eliminam tempo de pesquisa |
| **Comunicação** | Templates de e-mail prontos por severidade |
| **Aprendizado** | Post-mortems geram ações corretivas rastreadas |

Sem ITSM estruturado, o MTTR seria dominado pelo **tempo de coordenação humana** — não pelo tempo técnico de correção. A padronização deste documento é o que garante que qualquer membro do time consegue operar um incidente da mesma forma.

---

## Comunicação a Stakeholders — Templates

### Template — E-mail ao Comitê Gestor (P1)

**Assunto:** [P1] SolidaryTech — Incidente crítico em andamento

**Corpo:**
> Prezado Comitê,
>
> Informamos que às HH:MM (BRT) o serviço de processamento de doações da SolidaryTech apresentou instabilidade que impede a conclusão de novas doações.
>
> **Impacto observado:**
> - Serviço afetado: donation-service (recebimento de doações)
> - Duração até o momento: XX minutos
> - Doações potencialmente afetadas: ~XX (estimativa)
>
> **Status atual:**
> A equipe técnica está aplicando o procedimento de recuperação. Estimativa de restabelecimento: XX minutos.
>
> **Próximos passos:**
> - Novo e-mail assim que o serviço for restabelecido
> - Relatório detalhado (post-mortem) em até 5 dias úteis
>
> Att,
> DevOps Team — SolidaryTech

### Template — Status Page (público)

> **[Investigando]** Estamos com dificuldades para processar novas doações. Nossa equipe está trabalhando na resolução. Voluntariados e consultas seguem operando normalmente. Última atualização: HH:MM.

---

## Evidências de Operação

- [x] New Relic Applied Intelligence ativado sobre a stack OTel dos 3 serviços
- [x] Anomaly Detection configurado sem threshold manual
- [x] Error Inbox agregando erros por padrão
- [x] Log Patterns detectando mensagens recorrentes vs. anômalas
- [x] Ciclo de vida do incidente formalizado em 6 fases
- [x] Matriz de severidade P1-P4 definida
- [x] Matriz RACI documentada para eliminar ambiguidade
- [x] 4 runbooks operacionais escritos para os cenários mais comuns
- [x] Templates de comunicação prontos por severidade
- [x] Template de post-mortem blameless disponível

**Prints de evidência:**

![Applied Intelligence — Overview](./itsm/img/newrelic-ai-overview.png)
![Anomaly Detection ativo](./itsm/img/newrelic-anomaly-detection.png)
![Error Inbox — deduplicação de erros](./itsm/img/newrelic-error-inbox.png)

---

## Referências

- [ITIL 4 — Incident Management](https://www.axelos.com/certifications/itil-service-management)
- [Google SRE Book — Cap. 14: Managing Incidents](https://sre.google/sre-book/managing-incidents/)
- [Blameless PostMortem Culture — Etsy](https://www.etsy.com/codeascraft/blameless-postmortems)
- [New Relic Applied Intelligence Docs](https://docs.newrelic.com/docs/alerts-applied-intelligence/applied-intelligence/get-started/get-started-new-relic-applied-intelligence/)
