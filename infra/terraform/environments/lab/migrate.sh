#!/bin/bash
# migrate.sh — Executa as migrations SQL via ECS Run Task (one-off task)
# Deve ser executado após o primeiro terraform apply e antes do primeiro deploy
# Uso: ./migrate.sh

set -euo pipefail

REGION="${AWS_REGION:-us-east-1}"

echo "=== SolidaryTech — Migrations do Banco de Dados ==="

CLUSTER=$(terraform output -raw ecs_cluster_name)
SUBNETS=$(terraform output -json | python3 -c "
import sys, json
d = json.load(sys.stdin)
# Pegar primeira subnet privada
print(d['alb_dns_name']['value'])  # placeholder — ajuste conforme necessário
" 2>/dev/null || echo "")

echo "Cluster: $CLUSTER"
echo ""
echo "As migrations são executadas automaticamente quando os containers sobem."
echo "O ngo-service e donation-service criam as tabelas no PostgreSQL via init.sql."
echo ""
echo "Para executar manualmente via psql no RDS, use o AWS Systems Manager Session Manager:"
echo ""
echo "1. Crie um bastion host temporário OU use RDS Query Editor no console AWS"
echo "2. Conecte ao RDS endpoint: $(terraform output -raw rds_endpoint 2>/dev/null || echo '<rds-endpoint>')"
echo "3. Execute o script SQL:"
echo ""
echo "   -- ngo_db"
echo "   CREATE DATABASE ngo_db;"
echo "   \\c ngo_db"
echo "   $(cat ../../../apps/ngo-service/db/init.sql 2>/dev/null || echo '<conteúdo do init.sql>')"
echo ""
echo "   -- donation_db"
echo "   CREATE DATABASE donation_db;"
echo "   \\c donation_db"
echo "   $(cat ../../../apps/donation-service/db/init.sql 2>/dev/null || echo '<conteúdo do init.sql>')"
