#!/bin/bash
set -e

# =============================================================================
# Wiki 업데이트 모드
# MR 머지 후 호출되어 위키 저장소를 clone하고 Claude Code로 업데이트
# =============================================================================

: "${GITLAB_URL:?GITLAB_URL is required}"
: "${GITLAB_TOKEN:?GITLAB_TOKEN is required}"
: "${BOT_USERNAME:?BOT_USERNAME is required}"
: "${PROJECT_ID:?PROJECT_ID is required}"
: "${PROJECT_PATH:?PROJECT_PATH is required}"
: "${MR_IID:?MR_IID is required}"
: "${ANTHROPIC_API_KEY:?ANTHROPIC_API_KEY is required}"

GITLAB_API="${GITLAB_URL}/api/v4"
WIKI_DIR="/workspace/wiki"

echo "==> Wiki Update Mode"
echo "==> Project: ${PROJECT_PATH}"
echo "==> MR: !${MR_IID}"

# =============================================================================
# MR 상태 확인
# =============================================================================
echo "==> Checking MR status..."

MR_DATA=$(curl -s --max-time 15 --connect-timeout 5 \
    -H "PRIVATE-TOKEN: ${GITLAB_TOKEN}" \
    "${GITLAB_API}/projects/${PROJECT_ID}/merge_requests/${MR_IID}" || echo "{}")

MR_STATE=$(echo "$MR_DATA" | jq -r '.state // ""')
MR_TITLE=$(echo "$MR_DATA" | jq -r '.title // "Unknown"')

if [ "$MR_STATE" != "merged" ]; then
    echo "==> MR is not merged (state: ${MR_STATE}), skipping"
    exit 0
fi

# =============================================================================
# 위키 업데이트 지시사항 조회
# =============================================================================
echo "==> Fetching wiki update instructions..."

INSTRUCTION_PAGE=$(curl -s --max-time 15 --connect-timeout 5 \
    -H "PRIVATE-TOKEN: ${GITLAB_TOKEN}" \
    "${GITLAB_API}/projects/${PROJECT_ID}/wikis/mr%2F${MR_IID}" 2>/dev/null || echo "{}")

INSTRUCTIONS=$(echo "$INSTRUCTION_PAGE" | jq -r '.content // ""' 2>/dev/null || echo "")

if [ -z "$INSTRUCTIONS" ] || [ "$INSTRUCTIONS" = "null" ]; then
    echo "==> No wiki update instructions found for MR !${MR_IID}, skipping"
    exit 0
fi

echo "==> Found wiki update instructions"

# =============================================================================
# Git 설정
# =============================================================================
git config --global user.name "${BOT_USERNAME}"
git config --global user.email "${BOT_USERNAME}@fluffybot.local"
git config --global credential.helper store
echo "https://${BOT_USERNAME}:${GITLAB_TOKEN}@${GITLAB_URL#https://}" > ~/.git-credentials

# =============================================================================
# 위키 저장소 클론
# =============================================================================
echo "==> Cloning wiki repository..."

mkdir -p /workspace
cd /workspace

# 위키 저장소 URL
WIKI_REPO_URL="${GITLAB_URL}/${PROJECT_PATH}.wiki.git"

if git clone "$WIKI_REPO_URL" wiki 2>/dev/null; then
    echo "==> Wiki repository cloned successfully"
    cd wiki
else
    echo "==> Wiki repository does not exist, creating initial structure..."
    mkdir -p wiki
    cd wiki
    git init
    git remote add origin "$WIKI_REPO_URL"

    # 초기 Home 페이지 생성
    cat > Home.md << 'EOF'
# 프로젝트 위키

이 위키는 자동으로 관리됩니다.

## 페이지
- [[Recent-Changes]] - 최근 변경사항
- [[Architecture]] - 아키텍처
- [[Development-Guide]] - 개발 가이드
EOF

    cat > Recent-Changes.md << 'EOF'
# 최근 변경사항

이 페이지는 MR 머지 시 자동으로 업데이트됩니다.
EOF

    git add -A
    git commit -m "docs: 위키 초기화"
fi

# =============================================================================
# Claude Code로 위키 업데이트
# =============================================================================
echo "==> Running Claude Code for wiki update..."

CURRENT_DATE=$(date +"%Y-%m-%d")

cat > /tmp/wiki_prompt.txt << PROMPT_EOF
# 위키 업데이트 작업

## 지시사항
${INSTRUCTIONS}

## 작업 환경
- 현재 디렉토리가 위키 저장소입니다
- 위키 파일들은 마크다운(.md) 형식입니다
- 파일명이 곧 페이지 이름입니다 (예: Architecture.md → [[Architecture]])

## 필수 작업

1. 지시사항에 따라 해당 .md 파일들을 수정하세요
2. Recent-Changes.md에는 반드시 오늘 날짜(${CURRENT_DATE})와 MR !${MR_IID} 정보를 추가하세요
3. 새 페이지가 필요하면 새 .md 파일을 생성하세요
4. 수정 완료 후 커밋하세요:
   \`\`\`bash
   git add -A
   git commit -m "docs: MR !${MR_IID} 반영 - ${MR_TITLE}"
   \`\`\`

## 금지사항
- git push 하지 마세요 (스크립트가 처리)
- mr/ 폴더의 파일은 건드리지 마세요

**지금 작업을 시작하세요!**
PROMPT_EOF

# Claude Code 실행
set +e
claude -p "$(cat /tmp/wiki_prompt.txt)" --allowedTools "Bash,Read,Write,Edit,Glob,Grep" --verbose 2>&1 | tee /tmp/claude_wiki_output.log
CLAUDE_EXIT_CODE=$?
set -e

if [ $CLAUDE_EXIT_CODE -ne 0 ]; then
    echo "==> Warning: Claude Code failed, but continuing..."
fi

# =============================================================================
# 커밋 확인 및 푸시
# =============================================================================
echo "==> Checking for changes..."

git add -A
if ! git diff --cached --quiet; then
    echo "==> Found uncommitted changes, committing..."
    git commit -m "docs: MR !${MR_IID} 위키 업데이트" || true
fi

COMMIT_COUNT=$(git rev-list --count HEAD 2>/dev/null || echo "0")
if [ "$COMMIT_COUNT" -gt 0 ]; then
    echo "==> Pushing wiki changes..."
    git push -u origin HEAD:main || git push -u origin HEAD:master || {
        echo "==> Warning: Failed to push wiki changes"
    }
fi

# =============================================================================
# 지시사항 페이지 삭제
# =============================================================================
echo "==> Deleting instruction page mr/${MR_IID}..."

curl -s --max-time 10 -X DELETE \
    -H "PRIVATE-TOKEN: ${GITLAB_TOKEN}" \
    "${GITLAB_API}/projects/${PROJECT_ID}/wikis/mr%2F${MR_IID}" > /dev/null 2>&1 && \
    echo "==> Instruction page deleted" || \
    echo "==> Warning: Failed to delete instruction page"

# =============================================================================
# MR에 완료 코멘트 (중복 확인)
# =============================================================================
echo "==> Checking for existing completion comment in MR..."

# 기존 bot 코멘트 확인
EXISTING_MR_COMMENTS=$(curl -s --max-time 15 --connect-timeout 5 \
    -H "PRIVATE-TOKEN: ${GITLAB_TOKEN}" \
    "${GITLAB_API}/projects/${PROJECT_ID}/merge_requests/${MR_IID}/notes" 2>/dev/null || echo "[]")

COMPLETION_COMMENT_EXISTS=$(echo "$EXISTING_MR_COMMENTS" | jq -r --arg bot "$BOT_USERNAME" \
    '[.[] | select(.author.username == $bot and (.body | contains("📚 **위키 업데이트 완료**")))] | length' 2>/dev/null || echo "0")

if [ "$COMPLETION_COMMENT_EXISTS" = "0" ]; then
    echo "==> Posting completion comment..."

    WIKI_URL="${GITLAB_URL}/${PROJECT_PATH}/-/wikis"

    curl -s --max-time 15 -X POST \
        -H "PRIVATE-TOKEN: ${GITLAB_TOKEN}" \
        -H "Content-Type: application/json" \
        -d "$(jq -n --arg body "📚 **위키 업데이트 완료**

[프로젝트 위키 보기](${WIKI_URL})

---
🤖 Generated by ${BOT_USERNAME}" '{body: $body}')" \
        "${GITLAB_API}/projects/${PROJECT_ID}/merge_requests/${MR_IID}/notes" > /dev/null 2>&1
else
    echo "==> Skipping: Completion comment already exists in MR"
fi

echo "==> Done!"
