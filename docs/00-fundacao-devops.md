# Fundação DevOps (Requisito Obrigatório)

Registro da comprovação de utilização das disciplinas das Fases 1 a 4 no novo ecossistema de microsserviços.

## Docker

- [ ] Dockerfile otimizado — `ngo-service`
- [ ] Dockerfile otimizado — `donation-service`
- [ ] Dockerfile otimizado — `volunteer-service`

[01 - Docker](./fundacao/docker.md)   
[02 - Solidarytech Local](./fundacao/solidarytech-local.md  )

## Kubernetes

- Cloud/serviço utilizado: `AKS`
- [ ] Manifests de deploy dos 3 serviços
- [ ] Cluster provisionado e validado

## Infraestrutura como Código (Terraform)

- [ ] Módulo de networking  
- [ ] Módulo de cluster Kubernetes
- [ ] Módulo de banco de dados
- [ ] Módulo de mensageria (RabbitMQ/Redis)
- [ ] Módulo de registry (ACR/ECR)
- [ ] Tags FinOps aplicadas em todos os recursos (`Project`, `Environment`, `CostCenter`)

[01 - Infra](./fundacao/infra.md)  
[02 - Deploy Infra](./fundacao/deploy-infra.md)  

## CI/CD e DevSecOps

- [ ] Pipeline GitHub Actions configurado
- [ ] Testes automatizados no pipeline
- [ ] Scan SAST/SCA (Trivy/Sonar)
- [ ] Build e push de imagem para o registry



## GitOps

- Ferramenta utilizada: `ArgoCD `
- [ ] Aplicações configuradas via GitOps
- [ ] Deploy automático validado (sem `kubectl apply` manual)



## Observabilidade e APM

- [ ] Prometheus instalado
- [ ] Grafana instalado
- [ ] Loki e/ou OpenTelemetry configurado
- [ ] Instrumentação do APM (Datadog/New Relic)
- [ ] Distributed Tracing funcionando


