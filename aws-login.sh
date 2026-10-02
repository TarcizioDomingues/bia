#!/bin/bash

PROFILE="${1:-formacaoaws}"
REGION="us-east-1"
ECR_REGISTRY="100678005568.dkr.ecr.us-east-1.amazonaws.com"

echo "=== AWS Login ==="
echo "Profile: $PROFILE"
echo "Region:  $REGION"
echo

# Testa as credenciais AWS
if ! aws sts get-caller-identity \
  --profile "$PROFILE" \
  --region "$REGION"; then

  echo
  echo "ERRO: credenciais AWS nao encontradas ou invalidas."
  echo "Perfis disponíveis:"
  aws configure list-profiles
  exit 1
fi

echo
echo "AWS autenticada com sucesso."
echo
echo "=== Login no ECR ==="

aws ecr get-login-password \
  --region "$REGION" \
  --profile "$PROFILE" | \
docker login \
  --username AWS \
  --password-stdin "$ECR_REGISTRY"

if [ $? -eq 0 ]; then
  echo
  echo "AWS + ECR prontos para uso."
else
  echo
  echo "Falha no login do ECR."
  exit 1
fi
