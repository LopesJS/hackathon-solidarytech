#!/usr/bin/env bash
# =============================================================================
# lab-manage.sh — SolidaryTech Lab Infrastructure Manager v2
# =============================================================================

# NÃO usar set -e globalmente — capturamos erros manualmente com output claro
set -uo pipefail

# ─── Configuração ─────────────────────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Detecta automaticamente onde está o main.tf do lab
LAB_DIR=""
for candidate in \
  "${SCRIPT_DIR}/infra/terraform/environments/lab" \
  "${SCRIPT_DIR}/infra/terraform/environments/lab" \
  "${SCRIPT_DIR}/lab"; do
  if [[ -f "${candidate}/main.tf" ]]; then
    LAB_DIR="$candidate"
    break
  fi
done

REGION="${AWS_DEFAULT_REGION:-us-east-1}"
PROJECT="solidarytech"
CLUSTER="${PROJECT}-lab"
RDS_ID="${PROJECT}-lab-postgres"

# ─── Cores ────────────────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'

log_info()    { echo -e "${BLUE}[INFO]${NC}  $*"; }
log_ok()      { echo -e "${GREEN}[OK]${NC}    $*"; }
log_warn()    { echo -e "${YELLOW}[WARN]${NC}  $*"; }
log_error()   { echo -e "${RED}[ERROR]${NC} $*"; }
log_step()    { echo -e "\n${BOLD}${CYAN}━━━ $* ${NC}"; }
log_section() { echo -e "\n${BOLD}$*${NC}"; }

# ─── Verificar LAB_DIR antes de qualquer coisa ────────────────────────────────
check_lab_dir() {
  if [[ -z "$LAB_DIR" ]]; then
    log_error "Não foi possível encontrar terraform/environments/lab/main.tf"
    log_error "Estrutura esperada a partir de onde o script está:"
    log_error "  ./terraform/environments/lab/main.tf"
    log_error ""
    log_error "Estrutura encontrada:"
    find "$SCRIPT_DIR" -name "main.tf" 2>/dev/null | sed "s|$SCRIPT_DIR|.|" | head -10 || true
    log_error ""
    log_error "Posicione o lab-manage.sh na raiz do projeto solidarytech-infra"
    exit 1
  fi
  log_info "LAB_DIR: ${LAB_DIR}"
}

# ─── Pré-checks ───────────────────────────────────────────────────────────────
check_prerequisites() {
  log_step "Verificando pré-requisitos"

  local missing=0

  for cmd in terraform aws jq; do
    if command -v $cmd &> /dev/null; then
      log_ok "$cmd encontrado"
    else
      log_error "$cmd não encontrado — instale antes de continuar"
      missing=$((missing + 1))
    fi
  done

  if aws sts get-caller-identity &> /dev/null; then
    local account arn
    account=$(aws sts get-caller-identity --query Account --output text)
    arn=$(aws sts get-caller-identity --query Arn --output text)
    log_ok "AWS autenticado — conta: ${account}"
    log_info "Role: ${arn}"
  else
    log_error "Credenciais AWS inválidas ou expiradas"
    log_warn "No Vocareum: copie e exporte AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY, AWS_SESSION_TOKEN"
    missing=$((missing + 1))
  fi

  if [[ -z "${TF_VAR_db_password:-}" ]]; then
    log_error "TF_VAR_db_password não definida"
    log_warn "Execute: export TF_VAR_db_password='SuaSenha123!'"
    missing=$((missing + 1))
  else
    local pwd_len=${#TF_VAR_db_password}
    if [[ $pwd_len -lt 12 ]]; then
      log_error "Senha muito curta: ${pwd_len} chars (mínimo 12)"
      missing=$((missing + 1))
    else
      log_ok "TF_VAR_db_password definida (${pwd_len} caracteres)"
    fi
  fi

  if [[ $missing -gt 0 ]]; then
    log_error "${missing} problema(s) encontrado(s). Corrija antes de continuar."
    exit 1
  fi
}

# ─── Wrapper terraform com output visível ─────────────────────────────────────
tf_run() {
  local description="$1"
  shift
  log_info "Executando: terraform $*"
  if ! terraform "$@"; then
    log_error "Falha em: terraform $*"
    log_error "Veja o erro acima e corrija antes de continuar."
    exit 1
  fi
  log_ok "$description concluído"
}

# ─── UP ───────────────────────────────────────────────────────────────────────
cmd_up() {
  check_lab_dir
  check_prerequisites

  log_step "Provisionando SolidaryTech Lab"
  log_info "Diretório: ${LAB_DIR}"
  cd "$LAB_DIR"

  # Init — com output visível para diagnosticar falhas
  log_step "Init"
  if ! terraform init -input=false; then
    log_error "terraform init falhou."
    log_warn "Verifique se há conexão com a internet e se o provider AWS está acessível."
    exit 1
  fi
  log_ok "Init concluído"

  # ── Step 1A: Networking ─────────────────────────────────────────────────────
  log_step "STEP 1A — Networking"
  tf_run "Networking" apply \
    -target=module.networking \
    -var="db_password=${TF_VAR_db_password}" \
    -auto-approve

  _validate_networking

  # ── Step 1B: ECR ────────────────────────────────────────────────────────────
  log_step "STEP 1B — ECR"
  tf_run "ECR" apply \
    -target=module.ecr \
    -var="db_password=${TF_VAR_db_password}" \
    -auto-approve

  _validate_ecr

  # ── Step 2: SQS + DynamoDB ──────────────────────────────────────────────────
  log_step "STEP 2 — SQS + DynamoDB"
  tf_run "SQS + DynamoDB" apply \
    -target=module.sqs \
    -target=module.dynamodb \
    -var="db_password=${TF_VAR_db_password}" \
    -auto-approve

  _validate_sqs
  _validate_dynamodb

  # ── Step 3: RDS ─────────────────────────────────────────────────────────────
  log_step "STEP 3 — RDS PostgreSQL (~8-10 min)"
  tf_run "RDS" apply \
    -target=module.rds \
    -var="db_password=${TF_VAR_db_password}" \
    -auto-approve

  log_info "Aguardando RDS ficar available (pode levar até 10 min)..."
  if ! aws rds wait db-instance-available \
    --db-instance-identifier "$RDS_ID" \
    --region "$REGION"; then
    log_warn "Timeout aguardando RDS — verificando status atual..."
    aws rds describe-db-instances \
      --db-instance-identifier "$RDS_ID" \
      --query 'DBInstances[0].DBInstanceStatus' \
      --output text --region "$REGION" || true
  fi
  log_ok "RDS disponível"

  _validate_rds

  # ── Step 4: ECS ─────────────────────────────────────────────────────────────
  log_step "STEP 4 — ECS Fargate Spot"
  tf_run "ECS" apply \
    -target=module.ecs \
    -var="db_password=${TF_VAR_db_password}" \
    -auto-approve

  _validate_ecs

  # ── Step 5: Verificação final ────────────────────────────────────────────────
  log_step "STEP 5 — Verificação final"
  local exit_code=0
  terraform plan \
    -var="db_password=${TF_VAR_db_password}" \
    -detailed-exitcode \
    -no-color > /tmp/final-plan.txt 2>&1 || exit_code=$?

  if [[ $exit_code -eq 0 ]]; then
    log_ok "Infra 100% aplicada — nenhuma mudança pendente"
  elif [[ $exit_code -eq 2 ]]; then
    log_warn "Há mudanças pendentes. Rodando apply final..."
    terraform apply \
      -var="db_password=${TF_VAR_db_password}" \
      -auto-approve
  else
    log_error "Erro no plan final — verifique /tmp/final-plan.txt"
    cat /tmp/final-plan.txt | grep -E "Error|error" | head -20 || true
  fi

  _show_outputs
  _show_cost_summary
}

# ─── DOWN ─────────────────────────────────────────────────────────────────────
cmd_down() {
  check_lab_dir
  check_prerequisites

  log_step "Destruindo SolidaryTech Lab"
  echo ""
  log_warn "Esta operação irá DESTRUIR toda a infraestrutura:"
  log_warn "VPC, ECS, RDS, DynamoDB, SQS, ECR, CloudWatch Logs"
  echo ""
  read -rp "$(echo -e "${RED}Digite DESTRUIR para confirmar: ${NC}")" confirm

  if [[ "$confirm" != "DESTRUIR" ]]; then
    log_info "Operação cancelada."
    exit 0
  fi

  cd "$LAB_DIR"

  if ! terraform init -input=false -no-color > /dev/null 2>&1; then
    log_warn "Init falhou — tentando destroy mesmo assim..."
  fi

  log_info "Destruindo todos os recursos..."
  if ! terraform destroy \
    -var="db_password=${TF_VAR_db_password}" \
    -auto-approve; then
    log_error "Destroy falhou — alguns recursos podem precisar ser removidos manualmente no console."
    exit 1
  fi

  log_ok "Destroy concluído"
  echo ""
  _verify_cleanup
}

# ─── PAUSE ────────────────────────────────────────────────────────────────────
cmd_pause() {
  check_lab_dir
  check_prerequisites

  log_step "PAUSE — Destruindo NAT Gateway"
  log_info "Economia: ~\$32/mês enquanto pausado"
  log_info "ECS tasks não farão pull de novas imagens até resume"
  echo ""
  read -rp "Confirmar? (s/N): " confirm
  [[ "$confirm" != "s" && "$confirm" != "S" ]] && { log_info "Cancelado."; exit 0; }

  cd "$LAB_DIR"
  terraform init -input=false -no-color > /dev/null 2>&1 || true

  terraform destroy \
    -target=module.networking.aws_nat_gateway.main \
    -target="module.networking.aws_eip.nat[0]" \
    -var="db_password=${TF_VAR_db_password}" \
    -auto-approve

  log_ok "NAT Gateway destruído"
  log_warn "Use './lab-manage.sh resume' para retomar"
}

# ─── RESUME ───────────────────────────────────────────────────────────────────
cmd_resume() {
  check_lab_dir
  check_prerequisites

  log_step "RESUME — Recriando NAT Gateway"
  cd "$LAB_DIR"
  terraform init -input=false -no-color > /dev/null 2>&1 || true

  terraform apply \
    -target=module.networking.aws_nat_gateway.main \
    -target="module.networking.aws_eip.nat[0]" \
    -var="db_password=${TF_VAR_db_password}" \
    -auto-approve

  log_ok "NAT Gateway recriado"
  log_info "Aguardando 60s para as tasks estabilizarem..."
  sleep 60

  for svc in ngo-service donation-service volunteer-service; do
    aws ecs update-service \
      --cluster "$CLUSTER" \
      --service "$svc" \
      --force-new-deployment \
      --region "$REGION" > /dev/null 2>&1 && log_ok "Redeploy: $svc" || log_warn "Redeploy falhou: $svc"
  done
}

# ─── STATUS ───────────────────────────────────────────────────────────────────
cmd_status() {
  log_step "Status do SolidaryTech Lab"

  log_section "🌐 VPC"
  aws ec2 describe-vpcs \
    --filters "Name=tag:Project,Values=SolidaryTech" \
    --query 'Vpcs[*].{VpcId:VpcId,CIDR:CidrBlock,State:State}' \
    --output table --region "$REGION" 2>/dev/null \
    || log_warn "Nenhuma VPC encontrada"

  log_section "🔀 NAT Gateway"
  local nat_state
  nat_state=$(aws ec2 describe-nat-gateways \
    --filter "Name=tag:Project,Values=SolidaryTech" \
    --query 'NatGateways[0].State' \
    --output text --region "$REGION" 2>/dev/null || echo "none")
  case "$nat_state" in
    available) log_ok  "NAT Gateway: available (lab ligado)" ;;
    deleted|none) log_warn "NAT Gateway: ausente (lab pausado ou não criado)" ;;
    *) log_warn "NAT Gateway: ${nat_state}" ;;
  esac

  log_section "📦 ECR"
  aws ecr describe-repositories \
    --query 'repositories[?contains(repositoryName,`solidarytech`)].{Repo:repositoryName}' \
    --output table --region "$REGION" 2>/dev/null \
    || log_warn "Nenhum repositório ECR encontrado"

  log_section "🐳 ECS Services"
  aws ecs describe-services \
    --cluster "$CLUSTER" \
    --services ngo-service donation-service volunteer-service \
    --query 'services[*].{Service:serviceName,Status:status,Desired:desiredCount,Running:runningCount,Pending:pendingCount}' \
    --output table --region "$REGION" 2>/dev/null \
    || log_warn "Cluster ECS não encontrado"

  log_section "🗄️  RDS"
  aws rds describe-db-instances \
    --db-instance-identifier "$RDS_ID" \
    --query 'DBInstances[0].{Status:DBInstanceStatus,Host:Endpoint.Address,Class:DBInstanceClass,Encrypted:StorageEncrypted}' \
    --output json --region "$REGION" 2>/dev/null \
    || log_warn "RDS não encontrado"

  log_section "📨 SQS"
  aws sqs list-queues \
    --queue-name-prefix "$PROJECT" \
    --query 'QueueUrls' \
    --output table --region "$REGION" 2>/dev/null \
    || log_warn "Nenhuma fila SQS encontrada"

  log_section "⚡ DynamoDB"
  aws dynamodb list-tables \
    --query "TableNames[?contains(@,\`${PROJECT}\`)]" \
    --output table --region "$REGION" 2>/dev/null \
    || log_warn "Nenhuma tabela DynamoDB encontrada"

  log_section "🏷️  FinOps — recursos tagueados"
  local count
  count=$(aws resourcegroupstaggingapi get-resources \
    --tag-filters "Key=Project,Values=SolidaryTech" \
    --query 'length(ResourceTagMappingList)' \
    --output text --region "$REGION" 2>/dev/null || echo "0")
  log_info "Recursos com tag Project=SolidaryTech: ${count}"
}

# ─── VALIDATE ─────────────────────────────────────────────────────────────────
cmd_validate() {
  check_lab_dir
  log_step "Validação estática (sem tocar na AWS)"

  local modules_dir
  modules_dir="$(dirname "$(dirname "$LAB_DIR")")/modules"
  log_info "Módulos: ${modules_dir}"

  if [[ -d "$modules_dir" ]]; then
    for mod in "${modules_dir}"/*/; do
      name=$(basename "$mod")
      (
        cd "$mod"
        terraform init -backend=false -input=false -no-color > /dev/null 2>&1
        if terraform validate -no-color 2>&1 | grep -q "Success"; then
          echo -e "  ${GREEN}✓${NC} $name"
        else
          echo -e "  ${RED}✗${NC} $name — rode: terraform validate em $mod"
        fi
      )
    done
  fi

  cd "$LAB_DIR"
  log_info "Validando ambiente lab..."
  terraform init -backend=false -input=false -no-color > /dev/null 2>&1
  if terraform validate -no-color; then
    log_ok "Ambiente lab válido"
  else
    log_error "Ambiente lab com erros — corrija antes do apply"
    exit 1
  fi
}

# ─── Helpers de validação ─────────────────────────────────────────────────────
_validate_networking() {
  local count
  count=$(aws ec2 describe-vpcs \
    --filters "Name=tag:Project,Values=SolidaryTech" \
    --query 'length(Vpcs)' --output text --region "$REGION" 2>/dev/null || echo 0)
  [[ "$count" -ge 1 ]] && log_ok "VPC: OK" || log_warn "VPC não encontrada"

  count=$(aws ec2 describe-subnets \
    --filters "Name=tag:Project,Values=SolidaryTech" \
    --query 'length(Subnets)' --output text --region "$REGION" 2>/dev/null || echo 0)
  [[ "$count" -eq 4 ]] && log_ok "4 subnets: OK" || log_warn "Subnets: esperado 4, encontrado ${count}"
}

_validate_ecr() {
  local count
  count=$(aws ecr describe-repositories \
    --query 'length(repositories[?contains(repositoryName,`solidarytech`)])' \
    --output text --region "$REGION" 2>/dev/null || echo 0)
  [[ "$count" -eq 3 ]] && log_ok "3 repos ECR: OK" || log_warn "ECR: esperado 3, encontrado ${count}"
}

_validate_sqs() {
  local count
  count=$(aws sqs list-queues \
    --queue-name-prefix "$PROJECT" \
    --query 'length(QueueUrls)' --output text --region "$REGION" 2>/dev/null || echo 0)
  [[ "$count" -eq 3 ]] && log_ok "3 filas SQS: OK" || log_warn "SQS: esperado 3, encontrado ${count}"
}

_validate_dynamodb() {
  local count
  count=$(aws dynamodb list-tables \
    --query "length(TableNames[?contains(@,\`${PROJECT}\`)])" \
    --output text --region "$REGION" 2>/dev/null || echo 0)
  [[ "$count" -eq 2 ]] && log_ok "2 tabelas DynamoDB: OK" || log_warn "DynamoDB: esperado 2, encontrado ${count}"
}

_validate_rds() {
  local status
  status=$(aws rds describe-db-instances \
    --db-instance-identifier "$RDS_ID" \
    --query 'DBInstances[0].DBInstanceStatus' \
    --output text --region "$REGION" 2>/dev/null || echo "not-found")
  [[ "$status" == "available" ]] && log_ok "RDS: available" || log_warn "RDS: ${status}"
}

_validate_ecs() {
  local status
  status=$(aws ecs describe-clusters \
    --clusters "$CLUSTER" \
    --query 'clusters[0].status' \
    --output text --region "$REGION" 2>/dev/null || echo "not-found")
  [[ "$status" == "ACTIVE" ]] && log_ok "ECS cluster: ACTIVE" || log_warn "ECS: ${status}"
}

_verify_cleanup() {
  log_section "Verificando limpeza..."
  local vpc_count
  vpc_count=$(aws ec2 describe-vpcs \
    --filters "Name=tag:Project,Values=SolidaryTech" \
    --query 'length(Vpcs)' --output text --region "$REGION" 2>/dev/null || echo 0)
  [[ "$vpc_count" -eq 0 ]] && log_ok "VPC removida" || log_warn "VPC ainda presente (pode demorar)"

  local rds_count
  rds_count=$(aws rds describe-db-instances \
    --query "length(DBInstances[?contains(DBInstanceIdentifier,\`${PROJECT}\`)])" \
    --output text --region "$REGION" 2>/dev/null || echo 0)
  [[ "$rds_count" -eq 0 ]] && log_ok "RDS removido" || log_warn "RDS ainda removendo (~5 min)"
}

_show_outputs() {
  log_step "Outputs"
  cd "$LAB_DIR"
  terraform output 2>/dev/null || true
}

_show_cost_summary() {
  echo -e "
${BOLD}━━━ Estimativa de custo${NC}
  NAT Gateway     1x us-east-1     ~\$32.00/mês
  RDS PostgreSQL  db.t3.micro      ~\$12.00/mês
  ECS Fargate     3 tasks Spot     ~\$ 2.00/mês
  DynamoDB        On-demand        ~\$ 0.00/mês
  SQS + ECR       uso mínimo       ~\$ 0.50/mês
  ${BOLD}${GREEN}TOTAL                            ~\$46.50/mês${NC}

  ${YELLOW}💡 Use './lab-manage.sh pause' ao terminar o dia → economiza ~\$32/mês${NC}
"
}

# ─── Help ─────────────────────────────────────────────────────────────────────
cmd_help() {
  echo -e "
${BOLD}lab-manage.sh — SolidaryTech Lab Manager${NC}

${BOLD}COMANDOS:${NC}
  ${GREEN}up${NC}        Provisiona toda a infra (~18 min)
  ${RED}down${NC}      Destrói tudo (pede confirmação)
  ${CYAN}status${NC}    Status de todos os recursos
  ${YELLOW}pause${NC}     Destrói NAT GW (economia ~\$32/mês)
  ${YELLOW}resume${NC}    Recria NAT GW + força redeploy
  ${BLUE}validate${NC}  Valida código sem tocar na AWS

${BOLD}SETUP (a cada sessão no Vocareum):${NC}
  export AWS_ACCESS_KEY_ID='...'
  export AWS_SECRET_ACCESS_KEY='...'
  export AWS_SESSION_TOKEN='...'
  export AWS_DEFAULT_REGION='us-east-1'
  export TF_VAR_db_password='SuaSenha123!'

${BOLD}ESTRUTURA ESPERADA:${NC}
  solidarytech-infra/
  ├── lab-manage.sh        ← este script
  └── terraform/
      └── environments/
          └── lab/
              └── main.tf
"
}

# ─── Entry point ──────────────────────────────────────────────────────────────
case "${1:-help}" in
  up)       cmd_up ;;
  down)     cmd_down ;;
  status)   cmd_status ;;
  pause)    cmd_pause ;;
  resume)   cmd_resume ;;
  validate) cmd_validate ;;
  help|*)   cmd_help ;;
esac
