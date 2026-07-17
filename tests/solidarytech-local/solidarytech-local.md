# 🐳 SolidaryTech — Guia de Execução Local com Docker Compose

> Este guia detalha como qualquer pessoa, independente do sistema operacional, pode rodar a plataforma SolidaryTech completa em sua máquina usando Docker Compose — sem precisar instalar Go, Python, PostgreSQL ou qualquer outra dependência manualmente.

---

## Índice

1. [Pré-requisitos](#passo-1--pré-requisitos)
2. [Clonar o projeto e entender a estrutura](#passo-2--clonar-o-projeto-e-entender-a-estrutura)
3. [Gerar o arquivo go.sum](#passo-3--gerar-o-arquivo-gosum-donation-service)
4. [Configurar variáveis de ambiente](#passo-4--configurar-variáveis-de-ambiente)
5. [Criar o docker-compose.yml](#passo-5--criar-o-docker-composeyml)
6. [Subir o ambiente](#passo-6--subir-o-ambiente)
7. [Validar e testar os serviços](#passo-7--validar-e-testar-os-serviços)
8. [Encerrar o ambiente](#passo-8--encerrar-o-ambiente)

---

## Visão Geral da Arquitetura Local

Antes de começar, entenda o que vai rodar na sua máquina:

```
┌───────────────────────────────────────────────────────────┐
│                   Docker Compose (local)                  │
│                                                           │
│  ┌───────────────┐  ┌──────────────────┐  ┌─────────────┐ │
│  │  ngo-service  │  │ donation-service │  │ volunteer-  │ │
│  │  Python/Flask │  │      Go          │  │   service   │ │
│  │  porta: 8081  │  │  porta: 8082     │  │ Python/Flask│ │
│  └──────┬────────┘  └───────┬──────────┘  │ porta: 8083 │ │
│         │                   │             └──────┬──────┘ │
│         │                   │                    │        │
│  ┌──────▼───────────────────▼──┐  ┌─────────────▼──────┐  │
│  │   PostgreSQL 15             │  │    LocalStack      │  │
│  │   porta: 5432               │  │    porta: 4566     │  │
│  │   - banco: ngo_db           │  │    - DynamoDB      │  │
│  │   - banco: donation_db      │  │    - SQS           │  │
│  └─────────────────────────────┘  └────────────────────┘  │
└───────────────────────────────────────────────────────────┘
```

| Serviço | Tecnologia | Banco de dados | Porta |
|---|---|---|---|
| `ngo-service` | Python / Flask | PostgreSQL (`ngo_db`) | 8081 |
| `donation-service` | Go | PostgreSQL (`donation_db`) + SQS | 8082 |
| `volunteer-service` | Python / Flask | DynamoDB (LocalStack) | 8083 |
| `postgres` | PostgreSQL 15 | — | 5432 |
| `localstack` | LocalStack 3 | — | 4566 |

> **LocalStack** é uma ferramenta que simula serviços AWS (DynamoDB, SQS) localmente, sem precisar de conta AWS nem gerar custos.

---

## Passo 1 — Pré-requisitos

Você precisa ter instalado apenas duas ferramentas: **Docker** e **Go** (somente para gerar um arquivo de lock). Nada mais.

### 1.1 — Instalar o Docker Desktop

O Docker Desktop inclui tanto o `docker` quanto o `docker compose`.

| Sistema Operacional | Link de instalação |
|---|---|
| **macOS** (Intel ou Apple Silicon) | https://docs.docker.com/desktop/install/mac-install/ |
| **Windows** (WSL2 recomendado) | https://docs.docker.com/desktop/install/windows-install/ |
| **Linux (Ubuntu/Debian)** | https://docs.docker.com/desktop/install/linux-install/ |

Após instalar, abra o **Docker Desktop** e aguarde o ícone da baleia ficar verde na barra de tarefas/menu.

**Verificar se funcionou:**

```bash
docker --version
# Esperado: Docker version 25.x.x ou superior

docker compose version
# Esperado: Docker Compose version v2.x.x ou superior
```

> ⚠️ **Windows:** certifique-se de usar o **WSL2** como backend (configuração padrão do Docker Desktop). Todos os comandos a seguir devem ser executados no terminal do WSL2 (Ubuntu), não no PowerShell.

### 1.2 — Instalar o Go (apenas para o Passo 3)

O Go é necessário apenas para gerar o arquivo `go.sum` do `donation-service`. Após isso, não é mais necessário — o Docker cuida de tudo.

| Sistema Operacional | Comando |
|---|---|
| **macOS** | `brew install go` (requer [Homebrew](https://brew.sh)) |
| **Linux** | `sudo apt install golang-go` (Ubuntu/Debian) |
| **Windows** | Baixe o instalador em https://go.dev/dl/ |

**Verificar se funcionou:**

```bash
go version
# Esperado: go version go1.21.x ou superior
```

---

## Passo 2 — Clonar o projeto e entender a estrutura

### 2.1 — Clonar o repositório

```bash
git clone https://github.com/sua-org/solidarytech.git
cd solidarytech
```

### 2.2 — Estrutura esperada do projeto

Após clonar, a estrutura de pastas deve ser exatamente esta:

```
solidarytech/
│
├── ngo-service/
│   ├── app.py
│   ├── requirements.txt
│   ├── Dockerfile
│   ├── .dockerignore
│   └── db/
│       └── init.sql          ← Script SQL que cria a tabela `ngos`
│
├── donation-service/
│   ├── main.go
│   ├── go.mod
│   ├── go.sum                ← Será gerado no Passo 3 (pode não existir ainda)
│   ├── Dockerfile
│   ├── .dockerignore
│   └── db/
│       └── init.sql          ← Script SQL que cria a tabela `donations`
│
├── volunteer-service/
│   ├── app.py
│   ├── requirements.txt
│   ├── Dockerfile
│   ├── .dockerignore
│   └── db/                   ← (DynamoDB não usa SQL; tabela criada via CLI)
│
├── docker-compose.yml        ← Será criado no Passo 5
└── .env                      ← Será criado no Passo 4
```

> Se alguma pasta ou arquivo estiver faltando, revise o clone antes de continuar.

---

## Passo 3 — Gerar o arquivo `go.sum` (donation-service)

O `go.sum` é o arquivo de lock do Go — ele garante que as dependências baixadas são exatamente as esperadas (verificação de integridade). Ele precisa ser gerado uma única vez localmente.

```bash
# Entre na pasta do donation-service
cd donation-service

# Gera/atualiza o go.sum com base no go.mod
go mod tidy

# Volte para a raiz do projeto
cd ..
```

**Como confirmar que funcionou:**

```bash
ls donation-service/go.sum
# Deve exibir: donation-service/go.sum
```

> ✅ Após esse passo, o `go.sum` pode (e deve) ser commitado no repositório para que outros membros do time não precisem repeti-lo.

---

## Passo 4 — Configurar variáveis de ambiente

As variáveis de ambiente controlam como cada serviço se conecta aos bancos de dados e serviços AWS simulados. Para o ambiente local, criaremos um único arquivo `.env` na raiz do projeto.

### 4.1 — Criar o arquivo `.env`

Na **raiz do projeto** (`solidarytech/`), crie o arquivo `.env` com o conteúdo abaixo:

```bash
# Execute este comando para criar o arquivo automaticamente
cat > .env << 'EOF'
# ─── PostgreSQL ────────────────────────────────────────────────
POSTGRES_USER=solidary
POSTGRES_PASSWORD=solidary123
POSTGRES_DB=postgres

# ─── ngo-service ───────────────────────────────────────────────
NGO_DATABASE_URL=postgres://solidary:solidary123@postgres:5432/ngo_db

# ─── donation-service ──────────────────────────────────────────
DONATION_DATABASE_URL=postgres://solidary:solidary123@postgres:5432/donation_db
AWS_SQS_URL=http://localstack:4566/000000000000/solidary-donations

# ─── volunteer-service ─────────────────────────────────────────
AWS_DYNAMODB_TABLE=SolidaryTechVolunteers

# ─── AWS (simulado pelo LocalStack) ────────────────────────────
AWS_REGION=us-east-1
AWS_ACCESS_KEY_ID=test
AWS_SECRET_ACCESS_KEY=test
AWS_ENDPOINT_URL=http://localstack:4566
EOF
```

Ou, se preferir, crie o arquivo manualmente com qualquer editor de texto (VS Code, Nano, Notepad++, etc.) e cole o conteúdo acima.

> ⚠️ **Importante:** o arquivo `.env` nunca deve ser enviado ao repositório. Ele já está listado no `.gitignore` por padrão. As credenciais acima (`solidary123`, `test`) são apenas para uso local — **nunca as utilize em produção**.

### 4.2 — Ajuste necessário no `volunteer-service`

O `boto3` (SDK Python da AWS) não respeita a variável `AWS_ENDPOINT_URL` automaticamente em todas as versões. É necessário ajustar o `volunteer-service/app.py` para passar o endpoint do LocalStack explicitamente:

Localize este trecho no `volunteer-service/app.py`:

```python
# Trecho ORIGINAL (linha ~20)
dynamodb = boto3.resource("dynamodb", region_name=AWS_REGION)
table = dynamodb.Table(DYNAMODB_TABLE)
```

Substitua por:

```python
# Trecho AJUSTADO para suporte ao LocalStack
endpoint_url = os.getenv("AWS_ENDPOINT_URL")  # None em produção, URL do LocalStack em dev

dynamodb = boto3.resource(
    "dynamodb",
    region_name=AWS_REGION,
    endpoint_url=endpoint_url  # Se None, boto3 conecta nos endpoints reais da AWS
)
table = dynamodb.Table(DYNAMODB_TABLE)
```

> ✅ Esse ajuste é seguro para produção: quando `AWS_ENDPOINT_URL` não está definida (ambiente AWS real), o `boto3` conecta normalmente nos endpoints reais da AWS.

---

## Passo 5 — Criar o `docker-compose.yml`

Na **raiz do projeto** (`solidarytech/`), crie o arquivo `docker-compose.yml` com o conteúdo abaixo:

```yaml
# docker-compose.yml
# Orquestra todos os serviços da plataforma SolidaryTech para execução local.

services:

  # ─────────────────────────────────────────────────────────────────
  # INFRAESTRUTURA
  # ─────────────────────────────────────────────────────────────────

  postgres:
    image: postgres:15-alpine
    container_name: solidary-postgres
    environment:
      POSTGRES_USER: ${POSTGRES_USER}
      POSTGRES_PASSWORD: ${POSTGRES_PASSWORD}
      POSTGRES_DB: ${POSTGRES_DB}
    ports:
      - "5432:5432"                  # Permite acesso externo (ex: DBeaver, TablePlus)
    volumes:
      - postgres_data:/var/lib/postgresql/data   # Dados persistem entre restarts
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U ${POSTGRES_USER}"]
      interval: 10s
      timeout: 5s
      retries: 5
      start_period: 10s
    restart: unless-stopped

  localstack:
    image: localstack/localstack:3
    container_name: solidary-localstack
    ports:
      - "4566:4566"                  # Endpoint único para todos os serviços AWS simulados
    environment:
      SERVICES: dynamodb,sqs
      DEFAULT_REGION: ${AWS_REGION}
      PERSISTENCE: 1                 # Mantém dados entre restarts do container
    volumes:
      - localstack_data:/var/lib/localstack
    healthcheck:
      test: ["CMD-SHELL", "curl -sf http://localhost:4566/_localstack/health | grep -q '\"dynamodb\": \"running\"'"]
      interval: 15s
      timeout: 10s
      retries: 8
      start_period: 20s
    restart: unless-stopped

  # ─────────────────────────────────────────────────────────────────
  # INICIALIZAÇÃO DOS BANCOS DE DADOS
  # Rodam uma única vez para criar tabelas e dados de seed.
  # ─────────────────────────────────────────────────────────────────

  db-init:
    image: postgres:15-alpine
    container_name: solidary-db-init
    depends_on:
      postgres:
        condition: service_healthy
    environment:
      PGPASSWORD: ${POSTGRES_PASSWORD}
    volumes:
      - ./ngo-service/db/init.sql:/docker-entrypoint-initdb.d/01-init-ngo.sql:ro
      - ./donation-service/db/init.sql:/docker-entrypoint-initdb.d/02-init-donation.sql:ro
    entrypoint: >
      sh -c "
        echo '→ Criando banco ngo_db...' &&
        psql -h postgres -U ${POSTGRES_USER} -d postgres -c 'CREATE DATABASE ngo_db;' || echo 'ngo_db já existe.' &&
        echo '→ Criando banco donation_db...' &&
        psql -h postgres -U ${POSTGRES_USER} -d postgres -c 'CREATE DATABASE donation_db;' || echo 'donation_db já existe.' &&
        echo '→ Aplicando schema ngo-service...' &&
        psql -h postgres -U ${POSTGRES_USER} -d ngo_db -f /docker-entrypoint-initdb.d/01-init-ngo.sql &&
        echo '→ Aplicando schema donation-service...' &&
        psql -h postgres -U ${POSTGRES_USER} -d donation_db -f /docker-entrypoint-initdb.d/02-init-donation.sql &&
        echo '✓ Bancos de dados inicializados com sucesso.'
      "
    restart: on-failure

  aws-init:
    image: amazon/aws-cli:latest
    container_name: solidary-aws-init
    depends_on:
      localstack:
        condition: service_healthy
    environment:
      AWS_ACCESS_KEY_ID: ${AWS_ACCESS_KEY_ID}
      AWS_SECRET_ACCESS_KEY: ${AWS_SECRET_ACCESS_KEY}
      AWS_DEFAULT_REGION: ${AWS_REGION}
    entrypoint: >
      sh -c "
        echo '→ Criando tabela DynamoDB...' &&
        aws --endpoint-url=http://localstack:4566 dynamodb create-table \
          --table-name ${AWS_DYNAMODB_TABLE} \
          --attribute-definitions AttributeName=volunteer_id,AttributeType=S \
          --key-schema AttributeName=volunteer_id,KeyType=HASH \
          --billing-mode PAY_PER_REQUEST || echo 'Tabela já existe.' &&
        echo '→ Criando fila SQS...' &&
        aws --endpoint-url=http://localstack:4566 sqs create-queue \
          --queue-name solidary-donations || echo 'Fila já existe.' &&
        echo '✓ Recursos AWS (LocalStack) criados com sucesso.'
      "
    restart: on-failure

  # ─────────────────────────────────────────────────────────────────
  # MICROSSERVIÇOS
  # ─────────────────────────────────────────────────────────────────

  ngo-service:
    build:
      context: ./ngo-service
      dockerfile: Dockerfile
    image: solidarytech/ngo-service:local
    container_name: solidary-ngo-service
    ports:
      - "8081:8081"
    environment:
      PORT: "8081"
      DATABASE_URL: ${NGO_DATABASE_URL}
    depends_on:
      postgres:
        condition: service_healthy
      db-init:
        condition: service_completed_successfully
    healthcheck:
      test: ["CMD-SHELL", "python -c \"import urllib.request; urllib.request.urlopen('http://localhost:8081/health')\""]
      interval: 30s
      timeout: 5s
      retries: 3
      start_period: 15s
    restart: unless-stopped

  donation-service:
    build:
      context: ./donation-service
      dockerfile: Dockerfile
    image: solidarytech/donation-service:local
    container_name: solidary-donation-service
    ports:
      - "8082:8082"
    environment:
      PORT: "8082"
      DATABASE_URL: ${DONATION_DATABASE_URL}
      AWS_REGION: ${AWS_REGION}
      AWS_SQS_URL: ${AWS_SQS_URL}
      AWS_ACCESS_KEY_ID: ${AWS_ACCESS_KEY_ID}
      AWS_SECRET_ACCESS_KEY: ${AWS_SECRET_ACCESS_KEY}
    depends_on:
      postgres:
        condition: service_healthy
      db-init:
        condition: service_completed_successfully
      localstack:
        condition: service_healthy
      aws-init:
        condition: service_completed_successfully
    restart: unless-stopped

  volunteer-service:
    build:
      context: ./volunteer-service
      dockerfile: Dockerfile
    image: solidarytech/volunteer-service:local
    container_name: solidary-volunteer-service
    ports:
      - "8083:8083"
    environment:
      PORT: "8083"
      AWS_REGION: ${AWS_REGION}
      AWS_DYNAMODB_TABLE: ${AWS_DYNAMODB_TABLE}
      AWS_ACCESS_KEY_ID: ${AWS_ACCESS_KEY_ID}
      AWS_SECRET_ACCESS_KEY: ${AWS_SECRET_ACCESS_KEY}
      AWS_ENDPOINT_URL: ${AWS_ENDPOINT_URL}
    depends_on:
      localstack:
        condition: service_healthy
      aws-init:
        condition: service_completed_successfully
    healthcheck:
      test: ["CMD-SHELL", "python -c \"import urllib.request; urllib.request.urlopen('http://localhost:8083/health')\""]
      interval: 30s
      timeout: 5s
      retries: 3
      start_period: 15s
    restart: unless-stopped

volumes:
  postgres_data:       # Dados do PostgreSQL persistem entre `docker compose down` e `up`
  localstack_data:     # Dados do LocalStack (DynamoDB, SQS) persistem entre restarts
```

---

## Passo 6 — Subir o ambiente

Com tudo configurado, o ambiente sobe com um único comando.

### 6.1 — Primeiro build e start (pode levar alguns minutos)

```bash
# Na raiz do projeto (solidarytech/)
docker compose up --build
```

O que acontece em ordem:
1. Docker faz o **build** das 3 imagens (Python e Go)
2. **PostgreSQL** e **LocalStack** sobem e aguardam o health check passar
3. **`db-init`** cria os bancos `ngo_db` e `donation_db` e aplica os schemas
4. **`aws-init`** cria a tabela DynamoDB `SolidaryTechVolunteers` e a fila SQS
5. Os **3 microsserviços** sobem e ficam prontos para receber requisições

Você saberá que está tudo pronto quando ver logs parecidos com:

```
solidary-ngo-service       | [INFO] Listening at: http://0.0.0.0:8081
solidary-donation-service  | donation-service rodando na porta 8082
solidary-volunteer-service | [INFO] Listening at: http://0.0.0.0:8083
```

### 6.2 — Rodar em background (opcional)

Se não quiser o terminal preso com os logs, use a flag `-d` (detached):

```bash
docker compose up --build -d
```

Para ver os logs quando estiver em background:

```bash
# Todos os serviços
docker compose logs -f

# Um serviço específico
docker compose logs -f ngo-service
docker compose logs -f donation-service
docker compose logs -f volunteer-service
```

### 6.3 — Nas próximas vezes (sem rebuild)

Após o primeiro `--build`, nas execuções seguintes você não precisa rebuildar (a menos que mude o código):

```bash
docker compose up
```

---

## Passo 7 — Validar e testar os serviços

### 7.1 — Verificar se todos os containers estão saudáveis

```bash
docker compose ps
```

A coluna **STATUS** deve mostrar `running (healthy)` para todos os serviços principais:

```
NAME                         STATUS
solidary-postgres            running (healthy)
solidary-localstack          running (healthy)
solidary-ngo-service         running (healthy)
solidary-donation-service    running
solidary-volunteer-service   running (healthy)
```

> O `donation-service` usa imagem `distroless` (sem shell), portanto não tem health check configurável via Docker — mas estará funcionando se o log mostrar a porta ativa.

### 7.2 — Testar os health checks

```bash
curl http://localhost:8081/health
# {"service": "ngo-service", "status": "ok"}

curl http://localhost:8082/health
# {"service":"donation-service","status":"ok"}

curl http://localhost:8083/health
# {"service": "volunteer-service", "status": "ok"}
```

### 7.3 — Testar o fluxo completo

Execute os comandos abaixo em ordem para testar o fluxo real da plataforma:

**1. Listar ONGs (já vêm com dados de seed):**

```bash
curl http://localhost:8081/ngos
```

Resposta esperada:
```json
[
  {"id": 2, "name": "Educa Mais", "email": "info@educamais.org", "cause": "Educação", "city": "São Paulo", "created_at": "..."},
  {"id": 1, "name": "Anjos de Patas", "email": "contato@anjosdepatas.org", "cause": "Proteção Animal", "city": "Osasco", "created_at": "..."}
]
```

**2. Criar uma nova ONG:**

```bash
curl -X POST http://localhost:8081/ngos \
  -H "Content-Type: application/json" \
  -d '{
    "name": "Instituto Esperança",
    "email": "contato@esperanca.org",
    "cause": "Fome",
    "city": "Porto Alegre"
  }'
```

Resposta esperada (`201 Created`):
```json
{"id": 3, "name": "Instituto Esperança", "email": "contato@esperanca.org", "cause": "Fome", "city": "Porto Alegre", "created_at": "..."}
```

**3. Registrar uma doação:**

```bash
curl -X POST http://localhost:8082/donations \
  -H "Content-Type: application/json" \
  -d '{
    "ngo_id": 1,
    "amount": 150.00,
    "donor_name": "João Silva"
  }'
```

Resposta esperada (`201 Created`):
```json
{"id": 1, "ngo_id": 1, "amount": 150, "donor_name": "João Silva", "status": "APPROVED", "created_at": "..."}
```

**4. Listar doações:**

```bash
curl http://localhost:8082/donations
```

**5. Cadastrar um voluntário:**

```bash
curl -X POST http://localhost:8083/volunteers \
  -H "Content-Type: application/json" \
  -d '{
    "name": "Maria Costa",
    "email": "maria@email.com",
    "ngo_id": 1
  }'
```

Resposta esperada (`201 Created`):
```json
{"volunteer_id": "uuid-gerado", "name": "Maria Costa", "email": "maria@email.com", "ngo_id": 1, "registered_at": "..."}
```

**6. Buscar voluntários de uma ONG:**

```bash
curl http://localhost:8083/volunteers/1
```

### 7.4 — Conectar ao banco de dados (opcional)

Se quiser inspecionar os dados diretamente no PostgreSQL:

**Via terminal:**
```bash
docker exec -it solidary-postgres psql -U solidary -d ngo_db

# Dentro do psql:
\dt              -- lista as tabelas
SELECT * FROM ngos;
\q               -- sair
```

**Via ferramenta gráfica (DBeaver, TablePlus, pgAdmin):**

| Campo | Valor |
|---|---|
| Host | `localhost` |
| Porta | `5432` |
| Usuário | `solidary` |
| Senha | `solidary123` |
| Banco | `ngo_db` ou `donation_db` |

### 7.5 — Inspecionar o LocalStack (opcional)

```bash
# Listar tabelas DynamoDB criadas
docker exec solidary-localstack \
  awslocal dynamodb list-tables

# Ver itens na tabela de voluntários
docker exec solidary-localstack \
  awslocal dynamodb scan --table-name SolidaryTechVolunteers

# Listar filas SQS
docker exec solidary-localstack \
  awslocal sqs list-queues
```

### 7.6 — Problemas comuns e soluções

| Problema | Causa provável | Solução |
|---|---|---|
| `connection refused` em qualquer porta | Container ainda subindo | Aguarde 30–60s e tente novamente |
| `ngo_db does not exist` | `db-init` falhou | `docker compose logs db-init` para ver o erro |
| `volunteer-service` não conecta no DynamoDB | `AWS_ENDPOINT_URL` não foi lido pelo boto3 | Confirme o ajuste no `app.py` do Passo 4.2 |
| `go.sum` não encontrado no build | Passo 3 não foi executado | Rode `go mod tidy` dentro de `donation-service/` |
| Porta já em uso (`bind: address already in use`) | Outro processo usando a porta | Pare o processo local: `lsof -i :8081` e `kill -9 <PID>` |
| LocalStack health check falhando | LocalStack demora para iniciar | Normal no primeiro boot; aguarde ou aumente o `start_period` |

---

## Passo 8 — Encerrar o ambiente

### 8.1 — Parar os containers (mantém dados)

```bash
docker compose down
```

Os volumes (`postgres_data`, `localstack_data`) são preservados. Na próxima vez que subir com `docker compose up`, os dados ainda estarão lá.

### 8.2 — Parar e remover todos os dados

```bash
docker compose down -v
```

Use isso quando quiser começar do zero (limpa os volumes de banco de dados).

### 8.3 — Rebuild após mudanças no código

Se você alterar qualquer arquivo de código (`.py`, `.go`) ou dependências (`requirements.txt`, `go.mod`), é necessário rebuildar a imagem do serviço afetado:

```bash
# Rebuilda e reinicia apenas o serviço alterado
docker compose up --build ngo-service

# Ou rebuilda todos
docker compose up --build
```

### 8.4 — Remover imagens locais (limpeza completa)

```bash
# Remove containers, volumes, redes e imagens criadas pelo compose
docker compose down -v --rmi local

# Limpeza geral do Docker (remove tudo não utilizado)
docker system prune -af --volumes
```

> ⚠️ O comando `docker system prune` remove **todas** as imagens e volumes não utilizados no seu Docker, não apenas os do SolidaryTech.

---

## Referência rápida de comandos

```bash
# Subir tudo com build
docker compose up --build

# Subir em background
docker compose up -d

# Ver status dos containers
docker compose ps

# Ver logs em tempo real
docker compose logs -f

# Ver logs de um serviço
docker compose logs -f ngo-service

# Reiniciar um serviço
docker compose restart volunteer-service

# Parar (mantém dados)
docker compose down

# Parar e apagar dados
docker compose down -v
```

---

> Dúvidas ou problemas? Abra uma issue no repositório ou consulte a documentação completa de containerização em `CONTAINERIZATION.md`.
