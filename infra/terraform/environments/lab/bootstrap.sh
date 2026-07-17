#!/bin/bash
# bootstrap.sh — Cria os recursos de backend do Terraform (S3 + DynamoDB)
# Execute UMA VEZ antes do primeiro `terraform init`
# Requer: AWS CLI configurado com permissões suficientes

set -euo pipefail

REGION="${1:-us-east-1}"
BUCKET_NAME="solidarytech-tfstate-lab"
DYNAMODB_TABLE="solidarytech-tfstate-lock"

echo "=== SolidaryTech — Bootstrap do Backend Terraform ==="
echo "Região: $REGION"
echo "Bucket: $BUCKET_NAME"
echo "Tabela DynamoDB: $DYNAMODB_TABLE"
echo ""

# ─── S3 BUCKET ───────────────────────────────────────────────────────────────
echo "→ Criando bucket S3 para terraform state..."
if [ "$REGION" = "us-east-1" ]; then
  aws s3api create-bucket \
    --bucket "$BUCKET_NAME" \
    --region "$REGION"
else
  aws s3api create-bucket \
    --bucket "$BUCKET_NAME" \
    --region "$REGION" \
    --create-bucket-configuration LocationConstraint="$REGION"
fi

echo "→ Habilitando versionamento no bucket..."
aws s3api put-bucket-versioning \
  --bucket "$BUCKET_NAME" \
  --versioning-configuration Status=Enabled

echo "→ Habilitando criptografia no bucket..."
aws s3api put-bucket-encryption \
  --bucket "$BUCKET_NAME" \
  --server-side-encryption-configuration '{
    "Rules": [{
      "ApplyServerSideEncryptionByDefault": {
        "SSEAlgorithm": "AES256"
      }
    }]
  }'

echo "→ Bloqueando acesso público ao bucket..."
aws s3api put-public-access-block \
  --bucket "$BUCKET_NAME" \
  --public-access-block-configuration \
    "BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true"

# ─── DYNAMODB PARA STATE LOCK ─────────────────────────────────────────────────
echo "→ Criando tabela DynamoDB para state locking..."
aws dynamodb create-table \
  --table-name "$DYNAMODB_TABLE" \
  --attribute-definitions AttributeName=LockID,AttributeType=S \
  --key-schema AttributeName=LockID,KeyType=HASH \
  --billing-mode PAY_PER_REQUEST \
  --region "$REGION"

echo ""
echo "✓ Bootstrap concluído!"
echo ""
echo "Próximos passos:"
echo "  cd terraform/environments/lab"
echo "  terraform init"
echo "  terraform plan"
echo "  terraform apply"
