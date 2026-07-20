#!/bin/bash
# deploy.sh — Build das imagens, push para ECR e migrations do banco
# Executado após o `terraform apply` ter criado a infraestrutura
# Uso: ./deploy.sh [tag]

set -euo pipefail

REGION="${AWS_REGION:-us-east-1}"
GIT_SHA=$(git rev-parse --short HEAD 2>/dev/null || echo "local")
IMAGE_TAG="${1:-$GIT_SHA}"
APP_DIR="../../../../services"   # raiz do repo (4 níveis acima) + pasta services/

echo "=== SolidaryTech — Deploy das Imagens ==="
echo "Região: $REGION"
echo "Tag: $IMAGE_TAG"

# Pegar outputs do Terraform
echo "→ Lendo outputs do Terraform..."
ECR_NGO=$(terraform output -raw ecr_urls 2>/dev/null | python3 -c "import sys,json; d=json.load(sys.stdin); print(d['ngo-service'])" 2>/dev/null || echo "")

if [ -z "$ECR_NGO" ]; then
  echo "Erro: execute terraform apply antes deste script"
  exit 1
fi

ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
ECR_BASE="$ACCOUNT_ID.dkr.ecr.$REGION.amazonaws.com"

# ─── AUTENTICAR NO ECR ───────────────────────────────────────────────────────
echo "→ Autenticando no ECR..."
aws ecr get-login-password --region "$REGION" \
  | docker login --username AWS --password-stdin "$ECR_BASE"

# ─── BUILD E PUSH ────────────────────────────────────────────────────────────
SERVICES=("ngo-service" "donation-service" "volunteer-service")

for svc in "${SERVICES[@]}"; do
  echo ""
  echo "→ Building $svc..."
  docker build -t "solidarytech/$svc:$IMAGE_TAG" "$APP_DIR/$svc"

  ECR_URL="$ECR_BASE/solidarytech/$svc"
  docker tag "solidarytech/$svc:$IMAGE_TAG" "$ECR_URL:$IMAGE_TAG"
  docker tag "solidarytech/$svc:$IMAGE_TAG" "$ECR_URL:latest"

  echo "→ Pushing $svc para ECR..."
  docker push "$ECR_URL:$IMAGE_TAG"
  docker push "$ECR_URL:latest"

  echo "✓ $svc publicado: $ECR_URL:$IMAGE_TAG"
done

# ─── FORÇAR NOVO DEPLOY NO ECS ───────────────────────────────────────────────
echo ""
echo "→ Forçando novo deploy no ECS..."
CLUSTER=$(terraform output -raw ecs_cluster_name)

for svc in "ngo-service" "donation-service" "volunteer-service"; do
  aws ecs update-service \
    --cluster "$CLUSTER" \
    --service "$svc" \
    --force-new-deployment \
    --region "$REGION" \
    --no-cli-pager
  echo "✓ Deploy iniciado: $svc"
done

echo ""
ALB=$(terraform output -raw alb_dns_name)
echo "✓ Deploy concluído!"
echo ""
echo "Aguarde ~2 minutos e teste os endpoints:"
echo "  curl http://$ALB/health"
echo "  curl http://$ALB/ngos"
echo "  curl http://$ALB/donations"
echo "  curl http://$ALB/volunteers/1"
