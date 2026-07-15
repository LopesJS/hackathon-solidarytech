# SolidaryTech — Documentação do Hackathon

![Capa](/hackathon-solidarytech/images/capa.png)

Bem-vindo(a) à documentação técnica do projeto **SolidaryTech**, desenvolvida para o Hackathon da Fase 5 (POSTECH DCLT).

Esta documentação registra tudo o que foi realizado no projeto, organizado por tópicos atendendo a todos os requisitos.

## Sobre o projeto

A SolidaryTech é uma plataforma que conecta ONGs, doadores e voluntários. O desafio consistiu em construir, orquestrar, monitorar, otimizar financeiramente e criar a estratégia de resiliência para o novo ecossistema de microsserviços:

- **ngo-service** — cadastro e gestão de ONGs parceiras
- **donation-service** — processamento das doações (Caminho Crítico / Hot Path)
- **volunteer-service** — match entre voluntários e campanhas

## Equipe

| Nome | RM | GitHub | Discord |
|------|----|--------|------|
| Juliano da Silva Lopes | RM368967 | @LopesJS | juliano.lopes |

## Links importantes

- Vídeo de demonstração:
- Github do Projeto: [github.com/LopesJS/hackathon-solidarytech](https://github.com/LopesJS/hackathon-solidarytech) 
- Repositório base do desafio: [github.com/dougls/hackathon-DCLT](https://github.com/dougls/hackathon-DCLT)

## Como navegar nesta documentação

| Seção | Conteúdo |
|-------|----------|
| [Cronograma](cronograma.md) | Planejamento e datas do projeto |
| [0. Fundação DevOps](00-fundacao-devops.md) | Docker, Kubernetes, Terraform, CI/CD, GitOps, Observabilidade |
| [1. SRE](01-sre.md) | SLIs, SLOs, dashboard e MTTR |
| [2. FinOps](02-finops.md) | Tagging, rightsizing e forecast de custos |
| [3. ITSM e AIOps](03-itsm-aiops.md) | Gestão preditiva de incidentes |
| [4. DR e Segurança](04-dr-seguranca.md) | PCN, RTO/RPO e estratégia de disaster recovery |


## Arquitetura

![Arquitetura](/hackathon-solidarytech/images/arquitetura-geral.png)


