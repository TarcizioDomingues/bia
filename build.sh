#!/bin/bash
set -e

ECR_REGISTRY="100678005568.dkr.ecr.us-east-1.amazonaws.com"

echo ">> Login no ECR..."
aws ecr get-login-password --region us-east-1 | docker login --username AWS --password-stdin $ECR_REGISTRY

echo ">> Build da imagem..."
docker build -t bia .

echo ">> Tag e push para o ECR..."
docker tag bia:latest $ECR_REGISTRY/bia:latest
docker push $ECR_REGISTRY/bia:latest

echo ">> Deploy concluído: $ECR_REGISTRY/bia:latest"
