#!/bin/sh
set -e

echo "→ Criando tabela DynamoDB: ${AWS_DYNAMODB_TABLE}"
awslocal dynamodb create-table \
  --table-name "${AWS_DYNAMODB_TABLE}" \
  --attribute-definitions AttributeName=volunteer_id,AttributeType=S \
  --key-schema AttributeName=volunteer_id,KeyType=HASH \
  --billing-mode PAY_PER_REQUEST || echo "Tabela já existe, continuando..."

echo "→ Criando fila SQS: solidary-donations"
awslocal sqs create-queue \
  --queue-name solidary-donations || echo "Fila já existe, continuando..."

echo "✓ Recursos AWS criados com sucesso."
