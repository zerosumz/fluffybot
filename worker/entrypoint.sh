#!/bin/bash
set -e

# =============================================================================
# Fluffybot Worker Entrypoint
# =============================================================================
# 모드별 스크립트를 실행합니다:
# - issue: 이슈 작업 및 MR 생성 (기본값)
# - wiki: MR 머지 후 위키 업데이트
# =============================================================================

echo "==> Fluffybot Worker Starting..."
echo "==> Mode: ${TASK_MODE:-issue}"

case "${TASK_MODE:-issue}" in
  issue)
    echo "==> Executing issue work mode..."
    exec /scripts/issue-work.sh
    ;;
  wiki)
    echo "==> Executing wiki update mode..."
    exec /scripts/wiki-update.sh
    ;;
  *)
    echo "ERROR: Unknown mode: ${TASK_MODE}"
    echo "Valid modes: issue, wiki"
    exit 1
    ;;
esac
