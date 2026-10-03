#!/bin/bash

set -e

PROFILE="${1:-formacaoaws}"
REGION="us-east-1"

echo "======================================"
echo " AWS LOGIN"
echo "======================================"
echo "Profile: $PROFILE"
echo "Region:  $REGION"
echo

echo "Abrindo autenticação AWS..."
echo

aws login --profile "$PROFILE"

echo
echo "Verificando identidade..."
echo

aws sts get-caller-identity \
    --profile "$PROFILE" \
    --region "$REGION"

echo
echo "AWS autenticada com sucesso!"

ACCOUNT_ID=$(aws sts get-caller-identity \
    --profile "$PROFILE" \
    --query Account \
    --output text)

ECR_REGISTRY="${ACCOUNT_ID}.dkr.ecr.${REGION}.amazonaws.com"

echo
echo "Conta AWS: $ACCOUNT_ID"
echo "ECR: $ECR_REGISTRY"

echo
echo "======================================"
echo " LOGIN NO ECR"
echo "======================================"

aws ecr get-login-password \
    --region "$REGION" \
    --profile "$PROFILE" | \
docker login \
    --username AWS \
    --password-stdin "$ECR_REGISTRY"

echo
echo "======================================"
echo " AWS + ECR prontos para uso!"
echo "======================================"