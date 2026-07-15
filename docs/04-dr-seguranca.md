# 4. Multicloud, Segurança e Disaster Recovery (DR)

## Plano de Continuidade de Negócios (PCN)

| Item | Valor definido | Justificativa |
|------|------------------|-----------------|
| RTO (Recovery Time Objective) | | |
| RPO (Recovery Point Objective) | | |



## Estratégia de DR escolhida

- [x] Opção A — Multicloud/Cross-Region Backup (Velero)
- [ ] Opção B — Infraestrutura Ativo-Passivo (Terraform warm standby)

### Se Opção A (Velero)

- [ ] Velero instalado no cluster
- [ ] Backup do estado do cluster configurado (manifests + volumes)
- [ ] Bucket externo configurado como destino
- [ ] Teste de restauração realizado



### Se Opção B (Ativo-Passivo)

- [ ] Terraform modularizado para múltiplas regiões
- [ ] Ambiente "espelho" (warm standby) validado
- [ ] Subida do ambiente secundário testada com 1 comando


