# 2. FinOps — Otimização Financeira e Tagueamento

## Estratégia de Tagging (IaC)

Tags obrigatórias aplicadas via Terraform em todos os recursos:

| Tag | Valor |
|-----|-------|
| Project | SolidaryTech |
| Environment | Production |
| CostCenter | NGO-Core |



## Rightsizing

- [ ] Métricas de CPU/Memória analisadas
- [ ] `requests`/`limits` ajustados nos manifests YAML
- [ ] Ajustes aplicados via GitOps

**Antes → Depois:**

| Serviço | Requests antes | Requests depois | Limits antes | Limits depois |
|---------|-----------------|-------------------|----------------|------------------|
| ngo-service | | | | |
| donation-service | | | | |
| volunteer-service | | | | |

## Forecast de Custos

- [ ] Projeção mensal de custos da arquitetura elaborada
- [ ] Pelo menos 1 recomendação prática de otimização nativa da nuvem



**Recomendação de otimização:**

> Reserved Instances, Spot Instances, Savings Plans, autoscaling, etc.
