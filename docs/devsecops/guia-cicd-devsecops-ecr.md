# Guia — CI/CD DevSecOps (Build, Testes, SAST/SCA) e Push para o Registry (AWS ECR)

Com a infraestrutura já provisionada via Terraform. Este guia cobre a construção do **pipeline GitHub Actions** para os 3 microsserviços (`ngo-service`, `donation-service`, `volunteer-service`), rodando 100% na **AWS LAB**.

---

## Pré-requisitos gerais (antes de escrever qualquer YAML)

Confirme que você já tem cada um destes itens — eles são bloqueantes para os dois itens abaixo:

| # | Pré-requisito | Onde validar |
|---|-----------------|----------------|
| 1 | Repositório do código no GitHub (com os 3 serviços) | GitHub |
| 2 | Dockerfile funcional em cada um dos 3 serviços | build local: `docker build .` |
| 3 | **ECR (Elastic Container Registry)** criado na AWS LAB — 1 repositório por serviço | Terraform / Console AWS |
| 4 | Usuário/Role IAM com permissão de push no ECR | IAM |
| 5 | Credenciais da AWS LAB configuradas como **GitHub Secrets** | Settings → Secrets and variables → Actions |
| 6 | Conta gratuita no **SonarCloud** (ou SonarQube self-hosted) vinculada ao repositório | sonarcloud.io |
| 7 | Testes automatizados existentes no código (unitários, no mínimo) | pasta `tests/` de cada serviço |

> **Atenção AWS LAB:** ambientes de laboratório (ex: AWS Academy / Learner Lab) geram credenciais **temporárias** que expiram (geralmente em poucas horas) e não permitem criar Roles IAM novas em muitos casos. Isso muda a estratégia de autenticação do pipeline — trato isso no item de pré-requisitos do Item 2.

### 1. Criar os repositórios no ECR via Terraform

[Arquivo main.tf](/infra/terraform/modules/ecr/main.tf)



```bash
terraform apply -target=module.ecr
terraform output ecr_repository_urls
```

### 2. Configurar credenciais no GitHub (Secrets)

Vá em **Settings → Secrets and variables → Actions → New repository secret** e criar:

| Secret | Valor |
|--------|-------|
| `AWS_ACCESS_KEY_ID` | da AWS LAB (temporária) |
| `AWS_SECRET_ACCESS_KEY` | da AWS LAB (temporária) |
| `AWS_SESSION_TOKEN` | **obrigatório em labs** (credenciais temporárias exigem session token) |
| `AWS_ACCOUNT_ID` | ID da conta AWS LAB |
| `SONAR_TOKEN` | gerado no SonarCloud |

> **AWS LAB:** A sessão expira em 4 horas, logo, é necessário **atualizar essas 3 secrets da AWS manualmente toda vez que a sessão do lab expirar**.

---

## Item 1 — Pipeline GitHub Actions: Build, Testes, SAST/SCA

### O que cada etapa prova para a avaliação

| Etapa | O que comprova |
|-------|-------------------|
| Build | O código compila/empacota corretamente |
| Testes automatizados | Qualidade funcional mínima |
| SCA (Trivy) | Vulnerabilidades em dependências e na imagem Docker |
| SAST (SonarCloud) | Vulnerabilidades e code smells no código-fonte |

### Estrutura de pastas recomendada

```
.github/workflows/
  ├── ci-ngo-service.yml
  ├── ci-donation-service.yml
  └── ci-volunteer-service.yml
```

> Um workflow por serviço é mais simples de debugar em eventual manutenção.

### Pipeline completo:

Exemplo do arquivo desenvolvido para `donation-service`:

```yaml
# .github/workflows/ci-donation-service.yml
name: CI - donation-service

on:
  push:
    branches: [main, develop]
    paths:
      - 'donation-service/**'
  pull_request:
    paths:
      - 'donation-service/**'

env:
  SERVICE_NAME: donation-service
  WORKDIR: donation-service

jobs:
  # ---------- 1. BUILD ----------
  build:
    runs-on: ubuntu-latest
    defaults:
      run:
        working-directory: ${{ env.WORKDIR }}
    steps:
      - name: Checkout
        uses: actions/checkout@v4

      - name: Setup runtime (ajuste para sua linguagem)
        uses: actions/setup-node@v4   # troque por setup-python/setup-java conforme o serviço
        with:
          node-version: '20'

      - name: Install dependencies
        run: npm ci

      - name: Build
        run: npm run build --if-present

      - name: Upload build artifact
        uses: actions/upload-artifact@v4
        with:
          name: ${{ env.SERVICE_NAME }}-build
          path: ${{ env.WORKDIR }}/dist
          retention-days: 1

  # ---------- 2. TESTES AUTOMATIZADOS ----------
  test:
    needs: build
    runs-on: ubuntu-latest
    defaults:
      run:
        working-directory: ${{ env.WORKDIR }}
    steps:
      - uses: actions/checkout@v4

      - uses: actions/setup-node@v4
        with:
          node-version: '20'

      - name: Install dependencies
        run: npm ci

      - name: Run unit tests with coverage
        run: npm test -- --coverage

      - name: Upload coverage report
        uses: actions/upload-artifact@v4
        with:
          name: ${{ env.SERVICE_NAME }}-coverage
          path: ${{ env.WORKDIR }}/coverage

  # ---------- 3. SAST — SonarCloud ----------
  sast:
    needs: test
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
        with:
          fetch-depth: 0  # necessário para o Sonar analisar histórico corretamente

      - name: SonarCloud Scan
        uses: SonarSource/sonarcloud-github-action@master
        env:
          GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}
          SONAR_TOKEN: ${{ secrets.SONAR_TOKEN }}
        with:
          projectBaseDir: ${{ env.WORKDIR }}
          args: >
            -Dsonar.projectKey=solidarytech-donation-service
            -Dsonar.organization=<sua-org-sonarcloud>

  # ---------- 4. SCA/Vuln scan de dependências e Dockerfile — Trivy ----------
  sca:
    needs: test
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Trivy — scan do filesystem (dependências)
        uses: aquasecurity/trivy-action@master
        with:
          scan-type: 'fs'
          scan-ref: ${{ env.WORKDIR }}
          severity: 'CRITICAL,HIGH'
          format: 'table'
          exit-code: '1'   # falha o pipeline se achar CRITICAL/HIGH

      - name: Trivy — scan de configuração (Dockerfile, IaC)
        uses: aquasecurity/trivy-action@master
        with:
          scan-type: 'config'
          scan-ref: ${{ env.WORKDIR }}
          severity: 'CRITICAL,HIGH'
          exit-code: '0'   # não bloqueia ainda — modo "report only" para não travar seu prazo

  # ---------- 5. Build da imagem + scan da imagem ----------
  docker-scan:
    needs: [sast, sca]
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Build Docker image (local, sem push ainda)
        run: |
          docker build -t ${{ env.SERVICE_NAME }}:${{ github.sha }} ${{ env.WORKDIR }}

      - name: Trivy — scan da imagem Docker
        uses: aquasecurity/trivy-action@master
        with:
          image-ref: '${{ env.SERVICE_NAME }}:${{ github.sha }}'
          severity: 'CRITICAL,HIGH'
          format: 'table'
          exit-code: '1'
```

### Ordem de execução (grafo do pipeline)

```
build → test → sast → sca → docker-scan
```

`sast` e `sca` rodam em paralelo após os testes passarem, e o `docker-scan` só builda/escaneia a imagem depois que ambos os scans de código passaram — evitando gastar tempo de CI buildando imagem de código já reprovado.



### Checklist do Item 1

✅ Workflow criado para os 3 serviços
✅ Job de build passando
✅ Job de testes rodando com relatório de cobertura
✅ Trivy rodando scan de filesystem e de imagem
✅ Evidência: print da aba **Actions** com todos os jobs verdes + print do dashboard do Github Actions.



---

## Item 2 — Push de imagens para o Registry (AWS ECR)

### Pré-requisitos específicos deste item

1. **Repositórios ECR já criados** (Terraform, seção de pré-requisitos gerais acima)
2. **Autenticação Docker → ECR** funcionando (`aws ecr get-login-password`)
3. Decisão sobre **estratégia de tags** de imagem (recomendado: `git sha` + `latest` só na branch `main`)
4. Pipeline do Item 1 já passando (não faz sentido publicar imagem que não passou nos scans)

### Estratégia de autenticação recomendada para AWS LAB

Como labs normalmente **não permitem criar IAM Roles para OIDC** (o método "correto" e mais moderno seria `aws-actions/configure-aws-credentials` com OIDC, sem chaves fixas), a alternativa realista para o cenário foi usar as **chaves temporárias da sessão do lab** como Secrets, incluindo o `AWS_SESSION_TOKEN`.

> Em ambiente produtivo, a autenticação seria feita via OIDC/IAM Role sem chaves estáticas; no ambiente de AWS LAB utilizado, optou-se por credenciais temporárias de sessão devido às restrições de criação de IAM Roles no laboratório.

### Workflow — job de push (continuação do pipeline)



```yaml
  # ---------- 6. PUSH PARA O ECR ----------
  push-to-ecr:
    needs: docker-scan
    if: github.ref == 'refs/heads/main' && github.event_name == 'push'
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Configure AWS credentials (AWS LAB - sessão temporária)
        uses: aws-actions/configure-aws-credentials@v4
        with:
          aws-access-key-id: ${{ secrets.AWS_ACCESS_KEY_ID }}
          aws-secret-access-key: ${{ secrets.AWS_SECRET_ACCESS_KEY }}
          aws-session-token: ${{ secrets.AWS_SESSION_TOKEN }}
          aws-region: us-east-1

      - name: Login no ECR
        id: ecr-login
        uses: aws-actions/amazon-ecr-login@v2

      - name: Build, tag e push da imagem
        env:
          REGISTRY: ${{ steps.ecr-login.outputs.registry }}
          REPOSITORY: solidarytech/donation-service
          IMAGE_TAG: ${{ github.sha }}
        run: |
          docker build -t $REGISTRY/$REPOSITORY:$IMAGE_TAG donation-service/
          docker tag $REGISTRY/$REPOSITORY:$IMAGE_TAG $REGISTRY/$REPOSITORY:latest

          docker push $REGISTRY/$REPOSITORY:$IMAGE_TAG
          docker push $REGISTRY/$REPOSITORY:latest

      - name: Output da imagem publicada
        run: |
          echo "Imagem publicada: ${{ steps.ecr-login.outputs.registry }}/solidarytech/donation-service:${{ github.sha }}"
```

### Validar o push manualmente (fora do pipeline, para conferência rápida)

```bash
aws ecr describe-images \
  --repository-name solidarytech/donation-service \
  --region us-east-1
```

Ou pelo Console AWS: **ECR → Repositories → solidarytech/donation-service → Images**.


### Checklist do Item 2

- [ ] ECR criado para os 3 serviços (via Terraform)
- [ ] Secrets da AWS LAB configurados no GitHub (incluindo `AWS_SESSION_TOKEN`)
- [ ] Job de push condicionado a rodar só na `main` e só após os scans passarem
- [ ] Imagem publicada com tag `git sha` + `latest`
- [ ] Evidência: print do ECR mostrando as imagens publicadas com as tags corretas
- [ ] Limitação de credenciais temporárias documentada no relatório

---

