#!/bin/bash
set -e

ECR_REGISTRY="100678005568.dkr.ecr.us-east-1.amazonaws.com"
VITE_API_URL=${1:-""}

if [ -z "$VITE_API_URL" ]; then
  echo "Uso: ./build.sh <VITE_API_URL>"
  echo "Exemplo: ./build.sh http://meu-alb.us-east-1.elb.amazonaws.com"
  exit 1
fi

echo ">> Login no ECR..."
aws ecr get-login-password --region us-east-1 | docker login --username AWS --password-stdin $ECR_REGISTRY

echo ">> Build da imagem com VITE_API_URL=$VITE_API_URL ..."
docker build --build-arg VITE_API_URL=$VITE_API_URL -t bia .

echo ">> Tag e push para o ECR..."
docker tag bia:latest $ECR_REGISTRY/bia:latest
docker push $ECR_REGISTRY/bia:latest

echo ">> Deploy concluído: $ECR_REGISTRY/bia:latest"
