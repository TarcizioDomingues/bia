#!/bin/bash

set -e

export AWS_PROFILE=formacaoaws

# ============================================================
# CONFIGURAÇÃO DO AMBIENTE
# Para usar com ALB, altere as variáveis abaixo:
#   CLUSTER="cluster-bia-alb"
#   SERVICE="service-bia-alb"
#   TASK_DEF_FAMILY="task-def-bia-alb"
# ============================================================
REGION="us-east-1"
ECR_REGISTRY="100678005568.dkr.ecr.us-east-1.amazonaws.com"
ECR_REPOSITORY="bia"
CLUSTER="cluster-bia-alb"
SERVICE="service-bia-alb"
TASK_DEF_FAMILY="task-def-bia-alb"
CONTAINER_NAME="bia"

# ============================================================
# FUNÇÕES AUXILIARES
# ============================================================

usage() {
  echo "======================================"
  echo " BIA - DEPLOY ECS"
  echo "======================================"
  echo ""
  echo "Uso: $0 <comando> [opções]"
  echo ""
  echo "Comandos:"
  echo "  deploy              Faz build, push e deploy da versão atual do git"
  echo "  list                Lista as revisões disponíveis na task definition"
  echo "  rollback <revisão>  Faz rollback para a revisão informada"
  echo ""
  echo "Exemplos:"
  echo "  $0 deploy"
  echo "  $0 list"
  echo "  $0 rollback 15"
  echo ""
  echo "Ambiente atual:"
  echo "  Cluster:  $CLUSTER"
  echo "  Service:  $SERVICE"
  echo "  Task Def: $TASK_DEF_FAMILY"
  echo ""
}

check_dependencies() {
  for cmd in git docker aws jq; do
    if ! command -v "$cmd" &> /dev/null; then
      echo "[ERRO] Dependência não encontrada: $cmd"
      exit 1
    fi
  done
}

check_git_repo() {
  if ! git rev-parse --git-dir > /dev/null 2>&1; then
    echo "[ERRO] Não é um repositório git."
    exit 1
  fi
}

get_short_hash() {
  git rev-parse --short HEAD
}

# ============================================================
# COMANDO: LIST
# ============================================================

cmd_list() {
  echo "======================================"
  echo " BIA - VERSÕES DISPONÍVEIS"
  echo "======================================"
  echo ""
  echo "Família: $TASK_DEF_FAMILY"
  echo "Cluster: $CLUSTER | Service: $SERVICE"
  echo ""

  # Busca todas as revisões ativas
  TASK_DEF_ARNS=$(aws ecs list-task-definitions \
    --family-prefix "$TASK_DEF_FAMILY" \
    --status ACTIVE \
    --sort DESC \
    --region "$REGION" \
    --no-cli-pager \
    --query 'taskDefinitionArns[]' \
    --output json)

  if [ "$(echo "$TASK_DEF_ARNS" | jq 'length')" -eq 0 ]; then
    echo "[AVISO] Nenhuma task definition encontrada para a família '$TASK_DEF_FAMILY'."
    exit 0
  fi

  # Descobre qual revisão está em uso no service
  CURRENT_TASK_DEF=$(aws ecs describe-services \
    --cluster "$CLUSTER" \
    --services "$SERVICE" \
    --region "$REGION" \
    --no-cli-pager \
    --query 'services[0].taskDefinition' \
    --output text 2>/dev/null || echo "")

  CURRENT_REVISION=""
  if [ -n "$CURRENT_TASK_DEF" ]; then
    CURRENT_REVISION=$(echo "$CURRENT_TASK_DEF" | grep -oE '[0-9]+$')
  fi

  printf "%-10s %-15s %-45s %-28s %s\n" "REVISÃO" "STATUS" "IMAGEM (TAG)" "REGISTRADO EM" "EM USO"
  printf "%-10s %-15s %-45s %-28s %s\n" "--------" "------" "---------------------------------------------" "----------------------------" "-------"

  echo "$TASK_DEF_ARNS" | jq -r '.[]' | while read -r ARN; do
    REVISION=$(echo "$ARN" | grep -oE '[0-9]+$')

    DETAILS=$(aws ecs describe-task-definition \
      --task-definition "$ARN" \
      --region "$REGION" \
      --no-cli-pager \
      --query 'taskDefinition.{image:containerDefinitions[0].image,registeredAt:registeredAt}' \
      --output json)

    IMAGE=$(echo "$DETAILS" | jq -r '.image')
    IMAGE_TAG=$(echo "$IMAGE" | awk -F: '{print $NF}')
    REGISTERED_AT=$(echo "$DETAILS" | jq -r '.registeredAt' | sed 's/T/ /' | sed 's/\..*//')

    IN_USE=""
    if [ "$REVISION" = "$CURRENT_REVISION" ]; then
      IN_USE="<-- EM USO"
    fi

    printf "%-10s %-15s %-45s %-28s %s\n" "$REVISION" "ACTIVE" "$IMAGE_TAG" "$REGISTERED_AT" "$IN_USE"
  done

  echo ""
  echo "Para fazer rollback: $0 rollback <revisão>"
  echo ""
}

# ============================================================
# COMANDO: DEPLOY
# ============================================================

cmd_deploy() {
  check_git_repo

  COMMIT_HASH=$(get_short_hash)
  IMAGE_TAG="$COMMIT_HASH"
  FULL_IMAGE="$ECR_REGISTRY/$ECR_REPOSITORY:$IMAGE_TAG"
  FULL_IMAGE_LATEST="$ECR_REGISTRY/$ECR_REPOSITORY:latest"

  echo "======================================"
  echo " BIA - DEPLOY AWS"
  echo "======================================"
  echo ""
  echo "  Commit:   $COMMIT_HASH"
  echo "  Imagem:   $FULL_IMAGE"
  echo "  Cluster:  $CLUSTER"
  echo "  Service:  $SERVICE"
  echo ""

  echo "1. Verificando AWS..."
  aws sts get-caller-identity \
    --region "$REGION" \
    --no-cli-pager

  echo ""
  echo "2. Login no ECR..."
  aws ecr get-login-password \
    --region "$REGION" | \
  docker login \
    --username AWS \
    --password-stdin "$ECR_REGISTRY"

  echo ""
  echo "3. Build da imagem..."
  docker build -t "$ECR_REPOSITORY" .

  echo ""
  echo "4. Criando tags ($IMAGE_TAG e latest)..."
  docker tag "$ECR_REPOSITORY:latest" "$FULL_IMAGE"
  docker tag "$ECR_REPOSITORY:latest" "$FULL_IMAGE_LATEST"

  echo ""
  echo "5. Push para o ECR..."
  docker push "$FULL_IMAGE"
  docker push "$FULL_IMAGE_LATEST"

  echo ""
  echo "6. Buscando configuração atual da task definition..."
  CURRENT_TASK_DEF=$(aws ecs describe-task-definition \
    --task-definition "$TASK_DEF_FAMILY" \
    --region "$REGION" \
    --no-cli-pager \
    --query 'taskDefinition' \
    --output json)

  echo ""
  echo "7. Registrando nova task definition com imagem $IMAGE_TAG..."
  NEW_TASK_DEF=$(echo "$CURRENT_TASK_DEF" | jq \
    --arg IMAGE "$FULL_IMAGE" \
    --arg CONTAINER "$CONTAINER_NAME" \
    '.containerDefinitions |= map(if .name == $CONTAINER then .image = $IMAGE else . end)
    | del(.taskDefinitionArn, .revision, .status, .requiresAttributes, .registeredAt, .registeredBy, .compatibilities, .enableFaultInjection)')

  NEW_REVISION_ARN=$(aws ecs register-task-definition \
    --cli-input-json "$NEW_TASK_DEF" \
    --region "$REGION" \
    --no-cli-pager \
    --query 'taskDefinition.taskDefinitionArn' \
    --output text)

  NEW_REVISION=$(echo "$NEW_REVISION_ARN" | grep -oE '[0-9]+$')
  echo "   → Nova revisão registrada: $TASK_DEF_FAMILY:$NEW_REVISION"

  echo ""
  echo "8. Atualizando service ECS para revisão $NEW_REVISION..."
  aws ecs update-service \
    --cluster "$CLUSTER" \
    --service "$SERVICE" \
    --task-definition "$NEW_REVISION_ARN" \
    --region "$REGION" \
    --no-cli-pager > /dev/null

  echo ""
  echo "9. Aguardando serviço estabilizar..."
  aws ecs wait services-stable \
    --cluster "$CLUSTER" \
    --services "$SERVICE" \
    --region "$REGION"

  echo ""
  echo "======================================"
  echo " DEPLOY CONCLUÍDO!"
  echo "======================================"
  echo ""
  aws ecs describe-services \
    --cluster "$CLUSTER" \
    --services "$SERVICE" \
    --region "$REGION" \
    --no-cli-pager \
    --query 'services[0].{Running:runningCount,Pending:pendingCount,TaskDefinition:taskDefinition}' \
    --output table
  echo ""
  echo "  Commit deployado: $COMMIT_HASH"
  echo "  Task Definition:  $TASK_DEF_FAMILY:$NEW_REVISION"
  echo ""
}

# ============================================================
# COMANDO: ROLLBACK
# ============================================================

cmd_rollback() {
  TARGET_REVISION="$1"

  if [ -z "$TARGET_REVISION" ]; then
    echo "[ERRO] Informe o número da revisão para o rollback."
    echo ""
    echo "Uso: $0 rollback <revisão>"
    echo "Para ver revisões disponíveis: $0 list"
    exit 1
  fi

  # Valida se é número
  if ! [[ "$TARGET_REVISION" =~ ^[0-9]+$ ]]; then
    echo "[ERRO] A revisão deve ser um número inteiro. Recebido: '$TARGET_REVISION'"
    exit 1
  fi

  TARGET_TASK_DEF="$TASK_DEF_FAMILY:$TARGET_REVISION"

  echo "======================================"
  echo " BIA - ROLLBACK ECS"
  echo "======================================"
  echo ""
  echo "  Cluster:  $CLUSTER"
  echo "  Service:  $SERVICE"
  echo "  Alvo:     $TARGET_TASK_DEF"
  echo ""

  echo "1. Verificando AWS..."
  aws sts get-caller-identity \
    --region "$REGION" \
    --no-cli-pager

  echo ""
  echo "2. Verificando revisão $TARGET_REVISION..."
  TASK_DEF_DETAILS=$(aws ecs describe-task-definition \
    --task-definition "$TARGET_TASK_DEF" \
    --region "$REGION" \
    --no-cli-pager \
    --query 'taskDefinition.{status:status,image:containerDefinitions[0].image,registeredAt:registeredAt}' \
    --output json 2>&1) || {
    echo "[ERRO] Task definition '$TARGET_TASK_DEF' não encontrada."
    echo "Use '$0 list' para ver as revisões disponíveis."
    exit 1
  }

  STATUS=$(echo "$TASK_DEF_DETAILS" | jq -r '.status')
  IMAGE=$(echo "$TASK_DEF_DETAILS" | jq -r '.image')
  REGISTERED_AT=$(echo "$TASK_DEF_DETAILS" | jq -r '.registeredAt')

  echo "   → Status:    $STATUS"
  echo "   → Imagem:    $IMAGE"
  echo "   → Registrado: $REGISTERED_AT"

  if [ "$STATUS" != "ACTIVE" ]; then
    echo "[ERRO] A revisão $TARGET_REVISION está com status '$STATUS'. Apenas revisões ACTIVE podem ser usadas."
    exit 1
  fi

  echo ""
  echo "3. Verificando service atual..."
  CURRENT_TASK_DEF=$(aws ecs describe-services \
    --cluster "$CLUSTER" \
    --services "$SERVICE" \
    --region "$REGION" \
    --no-cli-pager \
    --query 'services[0].taskDefinition' \
    --output text)

  CURRENT_REVISION=$(echo "$CURRENT_TASK_DEF" | grep -oE '[0-9]+$')
  echo "   → Revisão em uso: $CURRENT_REVISION"
  echo "   → Rollback para:  $TARGET_REVISION"

  if [ "$CURRENT_REVISION" = "$TARGET_REVISION" ]; then
    echo ""
    echo "[AVISO] O service já está usando a revisão $TARGET_REVISION. Nada a fazer."
    exit 0
  fi

  echo ""
  echo "4. Atualizando service para $TARGET_TASK_DEF..."
  aws ecs update-service \
    --cluster "$CLUSTER" \
    --service "$SERVICE" \
    --task-definition "$TARGET_TASK_DEF" \
    --region "$REGION" \
    --no-cli-pager > /dev/null

  echo ""
  echo "5. Aguardando serviço estabilizar..."
  aws ecs wait services-stable \
    --cluster "$CLUSTER" \
    --services "$SERVICE" \
    --region "$REGION"

  echo ""
  echo "======================================"
  echo " ROLLBACK CONCLUÍDO!"
  echo "======================================"
  echo ""
  aws ecs describe-services \
    --cluster "$CLUSTER" \
    --services "$SERVICE" \
    --region "$REGION" \
    --no-cli-pager \
    --query 'services[0].{Running:runningCount,Pending:pendingCount,TaskDefinition:taskDefinition}' \
    --output table
  echo ""
}

# ============================================================
# MAIN
# ============================================================

check_dependencies

COMMAND="${1:-}"

case "$COMMAND" in
  deploy)
    cmd_deploy
    ;;
  list)
    cmd_list
    ;;
  rollback)
    cmd_rollback "$2"
    ;;
  *)
    usage
    exit 1
    ;;
esac
