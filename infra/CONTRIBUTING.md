# Contribuindo com Solidarytech Infra

## Fluxo de trabalho

1. Crie um branch a partir de `main`: `git checkout -b feat/descricao`
2. Faça suas alterações nos módulos ou environments
3. Rode `terraform fmt -recursive terraform/` antes de commitar
4. Abra um Pull Request — o CI rodará `terraform plan` automaticamente
5. Aguarde aprovação e merge

## Regras obrigatórias

- **Nunca aplique manualmente em produção** — use o workflow `terraform-apply` com approval
- **Toda mudança de módulo** deve atualizar `variables.tf` e `outputs.tf` correspondentes
- **Tags obrigatórias** devem estar em todos os recursos (use `merge(var.tags, {...})`)
- **Secrets** nunca em código — use GitHub Secrets → `TF_VAR_*`


## Estrutura de branches

| Branch | Propósito |
|--------|-----------|
| `main` | Produção — protegido, requer PR |
| `feat/*` | Novas funcionalidades |
| `fix/*`  | Correções |
| `chore/*`| Manutenção, atualizações de versão |
