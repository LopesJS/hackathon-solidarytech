# Cronograma — Hackathon 

**Projeto:** SolidaryTech  
**Início:** 29/07/2026  
**Entrega final:** 27/07/2026

---

## Status

- ✅ Fase 1 concluída
- ✅ Fase 2 concluída
- ⚠️ Fase 3 concluída
- ⚠️ Vídeo gravado
- ⚠️ Relatório PDF finalizado
- ⚠️ Projeto submetido

---


## 1. Visão Geral

| Fase | Objetivo | Foco Principal |
|---|--------|-----------------|
| 0 | Fundação DevOps (obrigatória) | Docker, Kubernetes, Terraform (IaC), CI/CD DevSecOps, GitOps, Observabilidade + APM. |
| 1 | SRE | SLIs/SLOs, dashboard de Error Budget, evidência de redução de MTTR. |
| 2 | FinOps | Tagging obrigatório no Terraform, rightsizing de pods, forecast de custos. |
| 3 | ITSM/AIOps | Ativação de AIOps (anomaly detection) + fluxo de gestão de incidentes. |
| 4 | Multicloud/Segurança/DR | PCN (RTO/RPO) + estratégia prática de DR (Velero). |


---

## 2. Cronograma Detalhado

### Semana 1 e 2 — Fundação DevOps

- ✅ **Kickoff**

  - Clonar repositório `hackathon-DCLT` e mapear os 3 microsserviços.
  - Definir de arquitetura e ferramentas.
  - Definição de cronograma.

- ✅ **Containerização**

  - Criar Dockerfiles otimizados (multi-stage) para os microserviços `ngo-service`, `donation-service`, `volunteer-service`.
  - Build local + testes de imagem (tamanho, camadas, healthcheck).

- ✅ **IaC: Rede e Cluster**

  - Terraform: módulo de networking (VNet/VPC, subnets).
  - Terraform: módulo do cluster Kubernetes (AKS/EKS/GKE).
  - Validação com `terraform plan` / `setup.sh` e validação de sintaxe.

- ✅ **IaC: Dados e Mensageria**

  - Terraform: banco de dados (RDS/Azure DB), Redis, RabbitMQ, ECR.
  - **Mapeamento e estratégia de Tagging FinOps**: `Project=SolidaryTech`, `Environment=Production`, `CostCenter=NGO-Core` em todos os recursos.

  - `terraform apply` do ambiente completo e testes
  - Documentação técnica.

- ✅ **CI/CD e DevSecOps**

  - Pipeline GitHub Actions: build, testes automatizados, scan SAST/SCA (Trivy/Sonar).
  - Push de imagens para o registry.

### Semana 3 e 4 — SRE, FinOps, ITSM/AIOps

- ⚠️ **GitOps**

  - Configuração ArgoCD.
  - Deploy dos 3 serviços via GitOps.

- ✅ **Observabilidade e APM**

  - Subir stack OpenTelemetry.
  - Instrumentar os 3 serviços no APM (Datadog ou New Relic) com Distributed Tracing.

- ⚠️ **SRE**

  - Definição de SLIs baseados em Golden Metrics.
  - Definição de SLOs.
  - Criar dashboard SRE dedicado (APM) com Error Budget.
  - Documentar como a stack reduz o MTTR.

- ⚠️ **FinOps**

  - Validar tags aplicadas em 100% dos recursos Terraform.
  - Analisar métricas de CPU/Memória e ajustar `requests`/`limits` via GitOps (rightsizing).
  - Relatório de forecast de custo mensal e recomendação de otimização nativa da nuvem.
  - Ajustar de dashboards e pipelines.

- ⚠️ **ITSM/AIOps**

  - Ativar funcionalidades de AIOps do APM (Watchdog/Applied Intelligence).
  - Desenhar o fluxo de vida do incidente: detecção (AIOps/alerta) → triagem → resolução → PostMortem → comunicação aos stakeholders.

### Semana 5 e 6 — DR/Segurança, integração e entrega

- ⚠️ **Disaster Recovery e PCN**

  - Escrever o Plano de Continuidade de Negócios (PCN): RTO e RPO para dados de doações.
  - Implementar estratégia prática de DR:
    - Opção A: Velero configurado para backup do cluster (manifests + volumes) em bucket externo.

- ⚠️ **Testes de integração ponta a ponta**

  - Validar pipeline completo: commit → CI/CD → ArgoCD → cluster.
  - Simular incidente e verificar alertas/AIOps/dashboard SRE reagindo.
  - Testar restauração de backup (Velero).

- ⚠️ **Relatório e vídeo**

  - Escrever o relatório final (.pdf): com links do repo e vídeo, evidências visuais de todas as seções (SRE, FinOps, DR, ITSM/AIOps).
  - Gravar o vídeo (15–20 min): arquitetura, PCN, estratégia financeira,pipelines rodando, ArgoCD, Terraform, Traces no APM, dashboard SRE, Backup/DR funcionais.

- ⚠️ **Revisão final e entrega**

  - Revisão do relatório e vídeo com o checklist de entregáveis.
  - Push final no repositório.
  - Submissão oficial.

---


