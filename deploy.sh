#!/bin/bash

set -e

export AWS_PROFILE=formacaoaws

REGION="us-east-1"
ECR_REGISTRY="100678005568.dkr.ecr.us-east-1.amazonaws.com"
ECR_REPOSITORY="bia"
CLUSTER="cluster-bia"
SERVICE="service-bia"

echo "======================================"
echo " BIA - DEPLOY AWS"
echo "======================================"

echo
echo "1. Verificando AWS..."
aws sts get-caller-identity \
  --region "$REGION" \
  --no-cli-pager

echo
echo "2. Login no ECR..."
aws ecr get-login-password \
  --region "$REGION" | \
docker login \
  --username AWS \
  --password-stdin "$ECR_REGISTRY"

echo
echo "3. Build da imagem..."
docker build -t bia .

echo
echo "4. Criando tag..."
docker tag \
  bia:latest \
  "$ECR_REGISTRY/$ECR_REPOSITORY:latest"

echo
echo "5. Push para o ECR..."
docker push \
  "$ECR_REGISTRY/$ECR_REPOSITORY:latest"

echo
echo "6. Iniciando novo deploy no ECS..."
aws ecs update-service \
  --cluster "$CLUSTER" \
  --service "$SERVICE" \
  --force-new-deployment \
  --region "$REGION" \
  --no-cli-pager > /dev/null

echo
echo "7. Aguardando nova task ficar estável..."
aws ecs wait services-stable \
  --cluster "$CLUSTER" \
  --services "$SERVICE" \
  --region "$REGION"

echo
echo "======================================"
echo " DEPLOY CONCLUIDO!"
echo "======================================"

aws ecs describe-services \
  --cluster "$CLUSTER" \
  --services "$SERVICE" \
  --region "$REGION" \
  --query 'services[0].{Running:runningCount,Pending:pendingCount,TaskDefinition:taskDefinition}' \
  --output table