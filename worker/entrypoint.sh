#!/bin/bash
set -e

# =============================================================================
# 환경변수 검증
# =============================================================================
: "${GITLAB_URL:?GITLAB_URL is required}"
: "${GITLAB_TOKEN:?GITLAB_TOKEN is required}"
: "${PROJECT_PATH:?PROJECT_PATH is required}"
: "${PROJECT_ID:?PROJECT_ID is required}"
: "${ISSUE_IID:?ISSUE_IID is required}"
: "${ANTHROPIC_API_KEY:?ANTHROPIC_API_KEY is required}"

GITLAB_API="${GITLAB_URL}/api/v4"
WORK_DIR="/workspace/project"

# =============================================================================
# 유틸리티 함수
# =============================================================================
post_comment() {
    local message="$1"
    curl -s --max-time 15 --connect-timeout 5 -X POST \
        -H "PRIVATE-TOKEN: ${GITLAB_TOKEN}" \
        -H "Content-Type: application/json" \
        -d "$(jq -n --arg body "$message" '{body: $body}')" \
        "${GITLAB_API}/projects/${PROJECT_ID}/issues/${ISSUE_IID}/notes" > /dev/null 2>&1 || \
        echo "Warning: Failed to post comment to GitLab" >&2
}

gitlab_api() {
    local endpoint="$1"
    curl -s --max-time 15 --connect-timeout 5 \
        -H "PRIVATE-TOKEN: ${GITLAB_TOKEN}" \
        "${GITLAB_API}${endpoint}" 2>/dev/null || echo "{}"
}

# =============================================================================
# Git 설정
# =============================================================================
git config --global user.name "Fluffybot"
git config --global credential.helper store
echo "https://fluffybot:${GITLAB_TOKEN}@${GITLAB_URL#https://}" > ~/.git-credentials

# =============================================================================
# 프로젝트 클론
# =============================================================================
echo "==> Cloning ${PROJECT_PATH}..."
mkdir -p /workspace
cd /workspace
git clone "${GITLAB_URL}/${PROJECT_PATH}.git" project
cd project

# CLAUDE.md 체크
if [ ! -f "CLAUDE.md" ]; then
    echo "ERROR: CLAUDE.md not found"
    post_comment "❌ CLAUDE.md 파일이 프로젝트 루트에 없습니다. AI Teammate를 사용하려면 CLAUDE.md를 추가해주세요."
    exit 1
fi

# =============================================================================
# 컨텍스트 수집
# =============================================================================
echo "==> Collecting context..."

# 1. CLAUDE.md 읽기
CONTEXT_CLAUDE_MD=$(cat CLAUDE.md)

# 2. Wiki 페이지 조회
echo "==> Fetching project wiki..."
WIKI_CONTEXT=""
WIKI_PAGES=$(curl -s --max-time 15 --connect-timeout 5 \
    -H "PRIVATE-TOKEN: ${GITLAB_TOKEN}" \
    "${GITLAB_API}/projects/${PROJECT_ID}/wikis" 2>/dev/null || echo "[]")

if [ "$WIKI_PAGES" != "[]" ] && [ -n "$WIKI_PAGES" ]; then
    WIKI_COUNT=$(echo "$WIKI_PAGES" | jq '. | length' 2>/dev/null || echo "0")
    echo "==> Found ${WIKI_COUNT} wiki page(s)"

    if [ "$WIKI_COUNT" -gt 0 ]; then
        # 각 위키 페이지 조회 및 결합
        WIKI_SLUGS=$(echo "$WIKI_PAGES" | jq -r '.[].slug' 2>/dev/null || echo "")

        if [ -n "$WIKI_SLUGS" ]; then
            WIKI_CONTEXT="# 프로젝트 위키

"
            while IFS= read -r slug; do
                [ -z "$slug" ] && continue

                echo "    - Fetching wiki page: ${slug}"
                WIKI_PAGE=$(curl -s --max-time 10 --connect-timeout 5 \
                    -H "PRIVATE-TOKEN: ${GITLAB_TOKEN}" \
                    "${GITLAB_API}/projects/${PROJECT_ID}/wikis/${slug}" 2>/dev/null || echo "{}")

                PAGE_TITLE=$(echo "$WIKI_PAGE" | jq -r '.title // ""' 2>/dev/null || echo "")
                PAGE_CONTENT=$(echo "$WIKI_PAGE" | jq -r '.content // ""' 2>/dev/null || echo "")

                if [ -n "$PAGE_TITLE" ] && [ -n "$PAGE_CONTENT" ]; then
                    WIKI_CONTEXT="${WIKI_CONTEXT}
## ${PAGE_TITLE}

${PAGE_CONTENT}

---

"
                fi
            done <<< "$WIKI_SLUGS"

            echo "==> Wiki context collected successfully"
        fi
    fi
else
    echo "==> No wiki pages found"
fi

# 3. 이슈 상세 정보 조회
ISSUE_DATA=$(gitlab_api "/projects/${PROJECT_ID}/issues/${ISSUE_IID}")
ISSUE_TITLE=$(echo "$ISSUE_DATA" | jq -r '.title')
ISSUE_DESCRIPTION=$(echo "$ISSUE_DATA" | jq -r '.description // ""')
ISSUE_LABELS=$(echo "$ISSUE_DATA" | jq -r '.labels | join(", ")')

# 4. 기존 브랜치 확인 (이슈 본문 및 코멘트에서 추출)
echo "==> Checking for existing branches..."

# 이슈 본문에서 브랜치 정보 추출
ISSUE_BRANCHES=$(echo "$ISSUE_DESCRIPTION" | grep -oP '브랜치:\s*`\K[^`]+' || true)
echo "==> Branches from issue description: ${ISSUE_BRANCHES:-none}"

# fluffybot 코멘트에서 브랜치 정보 추출 (타임아웃 추가)
echo "==> Fetching comments from GitLab API..."
COMMENTS_JSON=$(curl -s --max-time 15 --connect-timeout 5 \
    -H "PRIVATE-TOKEN: ${GITLAB_TOKEN}" \
    "${GITLAB_API}/projects/${PROJECT_ID}/issues/${ISSUE_IID}/notes" || echo "[]")

# 빈 응답 처리
if [ -z "$COMMENTS_JSON" ] || [ "$COMMENTS_JSON" = "null" ]; then
    echo "==> Warning: Empty response from GitLab API, skipping comment branch extraction"
    COMMENT_BRANCHES=""
else
    # jq로 fluffybot 코멘트 필터링 및 브랜치 추출
    FLUFFYBOT_COMMENTS=$(echo "$COMMENTS_JSON" | jq -r '.[] | select(.author.username == "fluffybot") | .body' 2>/dev/null || echo "")
    if [ -n "$FLUFFYBOT_COMMENTS" ]; then
        COMMENT_BRANCHES=$(echo "$FLUFFYBOT_COMMENTS" | grep -oP '작업 브랜치.*`\K[^`]+' || true)
        echo "==> Branches from fluffybot comments: ${COMMENT_BRANCHES:-none}"
    else
        echo "==> No fluffybot comments found"
        COMMENT_BRANCHES=""
    fi
fi

# 모든 후보 브랜치 수집 (빈 라인 제거)
ALL_BRANCHES=""
if [ -n "$ISSUE_BRANCHES" ]; then
    ALL_BRANCHES="${ISSUE_BRANCHES}"
fi
if [ -n "$COMMENT_BRANCHES" ]; then
    if [ -n "$ALL_BRANCHES" ]; then
        ALL_BRANCHES="${ALL_BRANCHES}
${COMMENT_BRANCHES}"
    else
        ALL_BRANCHES="${COMMENT_BRANCHES}"
    fi
fi

# 중복 제거 및 빈 라인 제거
if [ -n "$ALL_BRANCHES" ]; then
    ALL_BRANCHES=$(echo "$ALL_BRANCHES" | sort -u | grep -v '^$' | grep -v '^\s*$' || true)
fi

# 살아있는 브랜치 찾기
EXISTING_BRANCH=""
BRANCH_COUNT=0

# ALL_BRANCHES가 비어있지 않은지 다시 한번 확인
if [ -n "$ALL_BRANCHES" ] && [ "$ALL_BRANCHES" != "" ]; then
    echo "==> Found candidate branches, checking which ones exist on remote..."
    echo "==> Candidate branches:"
    echo "$ALL_BRANCHES" | while IFS= read -r line; do
        echo "    - $line"
    done

    echo "==> Fetching from origin (timeout: 30s)..."

    # git fetch에 타임아웃 추가 (GIT_TERMINAL_PROMPT=0으로 프롬프트 방지)
    export GIT_TERMINAL_PROMPT=0
    timeout 30s git fetch origin 2>&1 || {
        echo "==> Warning: git fetch timed out or failed, will try to check branches anyway"
    }

    # 브랜치 체크
    while IFS= read -r branch_name; do
        # 빈 줄이나 공백만 있는 줄 스킵
        if [ -z "$branch_name" ] || [ -z "${branch_name// /}" ]; then
            continue
        fi

        # 공백 제거
        branch_name=$(echo "$branch_name" | xargs)

        echo "==> Checking branch: '${branch_name}'"

        # git ls-remote에 타임아웃 추가
        if timeout 10s git ls-remote --heads origin "$branch_name" 2>&1 | grep -q "refs/heads/$branch_name"; then
            echo "    ✓ Branch exists: ${branch_name}"
            # 첫 번째로 찾은 살아있는 브랜치 사용
            if [ -z "$EXISTING_BRANCH" ]; then
                EXISTING_BRANCH="$branch_name"
            fi
            BRANCH_COUNT=$((BRANCH_COUNT + 1))
        else
            echo "    ✗ Branch not found or deleted: ${branch_name}"
        fi
    done <<< "$ALL_BRANCHES"
else
    echo "==> No candidate branches found, will create a new branch"
fi

if [ -n "$EXISTING_BRANCH" ]; then
    echo "==> Using existing branch: ${EXISTING_BRANCH}"
    [ $BRANCH_COUNT -gt 1 ] && echo "    (Note: Found ${BRANCH_COUNT} open branches, using first one)"

    git checkout "$EXISTING_BRANCH" 2>/dev/null || \
        git checkout -b "$EXISTING_BRANCH" origin/"$EXISTING_BRANCH"
    git pull origin "$EXISTING_BRANCH" --rebase || true
    BRANCH_NAME="$EXISTING_BRANCH"

    if [ $BRANCH_COUNT -gt 1 ]; then
        post_comment "🤖 작업을 계속합니다... (브랜치: \`${EXISTING_BRANCH}\`)

⚠️ **참고**: ${BRANCH_COUNT}개의 열린 브랜치가 발견되었습니다. 첫 번째 브랜치를 사용합니다."
    else
        post_comment "🤖 작업을 계속합니다... (브랜치: \`${EXISTING_BRANCH}\`)"
    fi
else
    echo "==> No existing branches found or all branches deleted, creating new branch"
    # Determine branch prefix based on labels
    BRANCH_PREFIX="feature"
    if echo "$ISSUE_LABELS" | grep -qi "bug"; then
        BRANCH_PREFIX="fix"
    fi
    BRANCH_NAME="${BRANCH_PREFIX}/${ISSUE_IID}-$(echo "$ISSUE_TITLE" | tr '[:upper:]' '[:lower:]' | tr -cs 'a-z0-9' '-' | head -c 30)"
    git checkout -b "$BRANCH_NAME"
    post_comment "🤖 작업을 시작합니다... (새 브랜치: \`${BRANCH_NAME}\`)"
fi

# 5. 참조된 이슈들 조회 (description에서 #123 형태 추출)
RELATED_ISSUES=""
ISSUE_REFS=$(echo "$ISSUE_DESCRIPTION" | grep -oP '#\K\d+' || true)
if [ -n "$ISSUE_REFS" ]; then
    echo "==> Fetching related issues..."
    for ref_iid in $ISSUE_REFS; do
        REF_DATA=$(gitlab_api "/projects/${PROJECT_ID}/issues/${ref_iid}" 2>/dev/null || echo "{}")
        REF_TITLE=$(echo "$REF_DATA" | jq -r '.title // "Not found"')
        REF_STATE=$(echo "$REF_DATA" | jq -r '.state // "unknown"')
        RELATED_ISSUES="${RELATED_ISSUES}
- #${ref_iid}: ${REF_TITLE} [${REF_STATE}]"
    done
fi

# 6. 최근 커밋 로그 (컨텍스트용)
RECENT_COMMITS=$(git log --oneline -10 2>/dev/null || echo "No commits")

# 7. 첨부파일 다운로드
ATTACHMENTS_DIR="/tmp/attachments"
ATTACHMENTS_INFO=""
SKIPPED_IMAGES=""
mkdir -p "$ATTACHMENTS_DIR"

echo "==> Checking for attachments..."
# GitLab 이슈의 description과 comments에서 /uploads/ 경로 추출
UPLOAD_URLS=$(echo "$ISSUE_DESCRIPTION" | grep -oP '(\(/uploads/[^)]+\)|/uploads/[^\s)]+)' | sed 's/[()]//g' || true)

if [ -n "$UPLOAD_URLS" ]; then
    echo "==> Found attachments, processing..."
    ATTACHMENT_COUNT=0
    SKIPPED_COUNT=0
    while IFS= read -r upload_path; do
        [ -z "$upload_path" ] && continue

        # 파일명 추출
        FILENAME=$(basename "$upload_path")
        FULL_URL="${GITLAB_URL}${upload_path}"
        DEST_PATH="${ATTACHMENTS_DIR}/${FILENAME}"

        # Content-Type 확인을 위해 HEAD 요청 (타임아웃 추가)
        CONTENT_TYPE=$(curl -s --max-time 10 --connect-timeout 5 -I \
            -H "PRIVATE-TOKEN: ${GITLAB_TOKEN}" "$FULL_URL" 2>/dev/null | \
            grep -i "^content-type:" | cut -d' ' -f2 | tr -d '\r\n' || echo "unknown")

        # 이미지 파일 여부 확인 - 이미지는 skip
        if [[ "$CONTENT_TYPE" =~ ^image/ ]] || [[ "$FILENAME" =~ \.(jpg|jpeg|png|gif|bmp|webp|svg)$ ]]; then
            SKIPPED_COUNT=$((SKIPPED_COUNT + 1))
            echo "    - Skipping image: $FILENAME (${CONTENT_TYPE})"
            SKIPPED_IMAGES="${SKIPPED_IMAGES}
- \`${FILENAME}\`"
        else
            # 일반 파일만 다운로드 (타임아웃 추가)
            echo "    - Downloading: $FILENAME"
            if curl -s --max-time 60 --connect-timeout 10 \
                -H "PRIVATE-TOKEN: ${GITLAB_TOKEN}" "$FULL_URL" -o "$DEST_PATH" 2>/dev/null; then
                FILE_SIZE=$(stat -c%s "$DEST_PATH" 2>/dev/null || stat -f%z "$DEST_PATH" 2>/dev/null || echo "0")
                FILE_SIZE_MB=$((FILE_SIZE / 1024 / 1024))

                ATTACHMENTS_INFO="${ATTACHMENTS_INFO}
- \`${DEST_PATH}\` (원본: ${FILENAME}, 크기: ${FILE_SIZE_MB}MB)"
                ATTACHMENT_COUNT=$((ATTACHMENT_COUNT + 1))
            else
                echo "    WARNING: Failed to download $FILENAME"
            fi
        fi
    done <<< "$UPLOAD_URLS"

    echo "==> Downloaded ${ATTACHMENT_COUNT} attachment(s), skipped ${SKIPPED_COUNT} image(s)"
else
    echo "==> No attachments found"
fi

# =============================================================================
# 프롬프트 파일 생성
# =============================================================================
echo "==> Preparing prompt..."

cat > /tmp/prompt.txt << PROMPT_EOF
# 프로젝트 컨텍스트

## CLAUDE.md
${CONTEXT_CLAUDE_MD}

$([ -n "$WIKI_CONTEXT" ] && echo "$WIKI_CONTEXT")

## 최근 커밋
\`\`\`
${RECENT_COMMITS}
\`\`\`

---

# 이슈 #${ISSUE_IID}: ${ISSUE_TITLE}

**라벨**: ${ISSUE_LABELS:-없음}

## 설명
${ISSUE_DESCRIPTION}

$([ -n "$RELATED_ISSUES" ] && echo "# 참조된 이슈들" && echo "$RELATED_ISSUES")

$([ -n "$ATTACHMENTS_INFO" ] && echo "# 첨부파일" && echo "$ATTACHMENTS_INFO" && echo "" && echo "**위 파일들은 Read 도구를 사용하여 내용을 확인할 수 있습니다. 텍스트, CSV, Excel, PDF 등의 데이터를 읽고 처리하세요.**")

$([ -n "$SKIPPED_IMAGES" ] && echo "# 스킵된 첨부파일 (이미지)" && echo "$SKIPPED_IMAGES" && echo "" && echo "**ℹ️ 이미지 파일은 Claude API 제한으로 인해 다운로드하지 않았습니다.**" && echo "**이미지 정보가 필요한 경우, 이슈 설명의 텍스트 내용을 참고하세요.**")

---

# 작업 지침

## 중요: 작업 환경
- **현재 디렉토리(${WORK_DIR})가 이미 클론된 프로젝트 루트입니다**
- **git clone 하지 마세요 - 이미 완료됨**
- **모든 작업은 현재 디렉토리에서 수행하세요**
- Git이 이미 설정되어 있습니다 (user.name: Fluffybot)
- 기존 브랜치: ${EXISTING_BRANCH:-없음} (없으면 새 브랜치 생성 필요)

## 필수 작업 순서

1. **브랜치 확인**:
   - 기존 브랜치가 있으면 (\`${EXISTING_BRANCH}\`) 해당 브랜치에서 작업 (이미 체크아웃됨)
   - 없으면 새 브랜치를 이미 생성했습니다 (\`${BRANCH_NAME}\`)
   - **브랜치는 이미 준비되어 있으므로 추가 생성 불필요**

2. **이슈 요구사항 구현**:
   - 위 이슈 설명에 따라 코드 작성/수정
   - 필요한 파일 읽기, 편집, 생성

3. **Git 커밋 (필수!)**:
   \`\`\`bash
   git add -A
   git commit -m "feat: 로그인 기능 추가"

   # 커밋 후 진행상황 코멘트 (필수!)
   curl -s -X POST \\
     -H "PRIVATE-TOKEN: ${GITLAB_TOKEN}" \\
     -H "Content-Type: application/json" \\
     -d "{\\"body\\": \\"📝 커밋: \$(git log -1 --pretty=%s)\\"}" \\
     "${GITLAB_API}/projects/${PROJECT_ID}/issues/${ISSUE_IID}/notes"
   \`\`\`
   - **반드시 git add -A 먼저 실행**
   - Conventional Commits: feat:, fix:, refactor:, docs:, test:, chore:
   - **커밋 메시지는 한글로 작성** (예: "feat: 사용자 인증 모듈 추가")
   - **커밋할 때마다 위 curl도 함께 실행하여 진행상황 코멘트 작성**

4. **브랜치 이름 저장 (필수!)**:
   \`\`\`bash
   echo "{현재-브랜치-이름}" > /tmp/branch_name
   \`\`\`

## 금지 사항
- git clone 하지 마세요 (이미 완료됨)
- git push 하지 마세요 (스크립트가 처리함)
- 사용자에게 질문하지 마세요 (비대화형 모드)

## 토큰 효율성
- 토큰 사용량이 커밋 메시지와 MR에 기록됩니다
- 불필요한 파일 읽기를 최소화하세요
- Task 에이전트는 꼭 필요할 때만 사용하세요

**지금 즉시 작업을 시작하고 완료하세요!**
PROMPT_EOF

# =============================================================================
# Claude Code 실행
# =============================================================================
echo "==> Running Claude Code..."
echo "==> Working directory: $(pwd)"

# 파일에서 읽어서 인자로 전달, 출력 캡처하여 토큰 사용량 추출
CLAUDE_OUTPUT_FILE="/tmp/claude_output.log"
CLAUDE_ERROR_FILE="/tmp/claude_error.log"

# Claude Code 실행 (exit code 캡처)
set +e  # 일시적으로 에러 발생 시 스크립트 중단 비활성화
claude -p "$(cat /tmp/prompt.txt)" --allowedTools "Bash,Read,Write,Edit,Glob,Grep" --verbose 2>&1 | tee "$CLAUDE_OUTPUT_FILE"
CLAUDE_EXIT_CODE=$?
set -e  # 다시 활성화

# 실행 실패 시 상세 오류 분석 및 코멘트 작성
if [ $CLAUDE_EXIT_CODE -ne 0 ]; then
    echo "ERROR: Claude Code failed with exit code ${CLAUDE_EXIT_CODE}"

    # 오류 타입 분석
    ERROR_TYPE="unknown"
    ERROR_DETAIL=""

    # 토큰 부족 오류
    if grep -qi "insufficient.*quota\|quota.*exceeded\|usage.*limit" "$CLAUDE_OUTPUT_FILE"; then
        ERROR_TYPE="quota_exceeded"
        ERROR_DETAIL="API 사용량 한도가 초과되었습니다. 잠시 후 다시 시도해주세요."
    # 토큰 제한 오류
    elif grep -qi "token.*limit\|context.*too.*large\|too.*many.*tokens" "$CLAUDE_OUTPUT_FILE"; then
        ERROR_TYPE="token_limit"
        ERROR_DETAIL="프롬프트가 너무 큽니다. 이슈 설명을 간결하게 줄이거나 첨부파일을 줄여주세요."
    # API 키 오류
    elif grep -qi "invalid.*api.*key\|authentication.*failed\|unauthorized" "$CLAUDE_OUTPUT_FILE"; then
        ERROR_TYPE="auth_error"
        ERROR_DETAIL="Claude API 인증에 실패했습니다. API 키를 확인해주세요."
    # API 오류
    elif grep -qi "api.*error\|service.*unavailable\|connection.*error" "$CLAUDE_OUTPUT_FILE"; then
        ERROR_TYPE="api_error"
        ERROR_DETAIL="Claude API 서버에 연결할 수 없습니다. 잠시 후 다시 시도해주세요."
    # 타임아웃
    elif grep -qi "timeout\|timed.*out" "$CLAUDE_OUTPUT_FILE"; then
        ERROR_TYPE="timeout"
        ERROR_DETAIL="작업 시간이 초과되었습니다. 이슈를 더 작은 단위로 나누어주세요."
    # 권한 오류
    elif grep -qi "permission.*denied\|access.*denied" "$CLAUDE_OUTPUT_FILE"; then
        ERROR_TYPE="permission_error"
        ERROR_DETAIL="파일 접근 권한이 없습니다. 저장소 권한을 확인해주세요."
    else
        # 기타 오류: 마지막 몇 줄 추출
        ERROR_DETAIL=$(tail -20 "$CLAUDE_OUTPUT_FILE" | grep -i "error\|fail\|exception" | head -5 || echo "상세 오류 정보를 확인할 수 없습니다.")
    fi

    # 토큰 사용량 추출 시도 (여러 패턴)
    TOKEN_USAGE=$(grep -oP 'Token usage:\s*\K[0-9,]+/[0-9,]+' "$CLAUDE_OUTPUT_FILE" | tail -1 || echo "")
    [ -z "$TOKEN_USAGE" ] && TOKEN_USAGE=$(grep -oP '[0-9,]+/[0-9,]+(?=\s+tokens?)' "$CLAUDE_OUTPUT_FILE" | tail -1 || echo "")
    [ -z "$TOKEN_USAGE" ] && TOKEN_USAGE=$(grep -oP '\b[0-9]{4,6}/[0-9]{5,7}\b' "$CLAUDE_OUTPUT_FILE" | tail -1 || echo "")
    [ -z "$TOKEN_USAGE" ] && TOKEN_USAGE="unknown"

    # 상세 오류 코멘트 작성
    ERROR_COMMENT="❌ **Claude Code 실행 실패**

**오류 타입**: \`${ERROR_TYPE}\`
**Exit Code**: ${CLAUDE_EXIT_CODE}

**상세 정보**:
${ERROR_DETAIL}"

    [ "$TOKEN_USAGE" != "unknown" ] && ERROR_COMMENT="${ERROR_COMMENT}

**토큰 사용량**: ${TOKEN_USAGE}"

    ERROR_COMMENT="${ERROR_COMMENT}

**전체 로그는 Job Pod 로그를 확인해주세요.**"

    post_comment "$ERROR_COMMENT"
    exit 1
fi

# 토큰 사용량 추출 (여러 패턴 시도)
echo "==> Extracting token usage..."
TOKEN_USAGE="unknown"

# 패턴 1: "Token usage: 15000/200000" 형식
if [ "$TOKEN_USAGE" = "unknown" ]; then
    TOKEN_USAGE=$(grep -oP 'Token usage:\s*\K[0-9,]+/[0-9,]+' "$CLAUDE_OUTPUT_FILE" | tail -1 || echo "")
    [ -z "$TOKEN_USAGE" ] && TOKEN_USAGE="unknown"
fi

# 패턴 2: "15000/200000 tokens" 형식
if [ "$TOKEN_USAGE" = "unknown" ]; then
    TOKEN_USAGE=$(grep -oP '[0-9,]+/[0-9,]+(?=\s+tokens?)' "$CLAUDE_OUTPUT_FILE" | tail -1 || echo "")
    [ -z "$TOKEN_USAGE" ] && TOKEN_USAGE="unknown"
fi

# 패턴 3: 단순히 "숫자/숫자" 패턴 (마지막 매칭)
if [ "$TOKEN_USAGE" = "unknown" ]; then
    TOKEN_USAGE=$(grep -oP '\b[0-9]{4,6}/[0-9]{5,7}\b' "$CLAUDE_OUTPUT_FILE" | tail -1 || echo "")
    [ -z "$TOKEN_USAGE" ] && TOKEN_USAGE="unknown"
fi

echo "==> Token usage: ${TOKEN_USAGE}"

# 디버깅용: 토큰 관련 라인 출력
echo "==> Token-related lines in output:"
grep -i "token\|usage" "$CLAUDE_OUTPUT_FILE" | tail -5 || echo "  (none found)"

# =============================================================================
# 안전장치: Claude가 커밋 빼먹었을 경우 대비
# =============================================================================
echo "==> Checking for uncommitted changes..."
echo "==> Current directory: $(pwd)"
echo "==> Git status:"
git status --short

git add -A
if ! git diff --cached --quiet; then
    echo "==> Found uncommitted changes, committing..."
    COMMIT_MSG="feat(#${ISSUE_IID}): automated changes by fluffybot"
    [ "$TOKEN_USAGE" != "unknown" ] && COMMIT_MSG="${COMMIT_MSG} [tokens: ${TOKEN_USAGE}]"
    git commit -m "$COMMIT_MSG"
fi

# 브랜치 이름 확인
if [ ! -f /tmp/branch_name ]; then
    echo "WARNING: /tmp/branch_name not found, using current branch"
    git branch --show-current > /tmp/branch_name
fi
BRANCH_NAME=$(cat /tmp/branch_name | tr -d '\n')

# 현재 브랜치 확인
CURRENT_BRANCH=$(git branch --show-current)
echo "==> Current branch: ${CURRENT_BRANCH}"
echo "==> Expected branch: ${BRANCH_NAME}"

if [ "$CURRENT_BRANCH" = "main" ] || [ "$CURRENT_BRANCH" = "master" ] || [ "$CURRENT_BRANCH" = "develop" ]; then
    echo "ERROR: Still on ${CURRENT_BRANCH} branch. Claude did not create a feature branch."
    post_comment "❌ 브랜치 생성에 실패했습니다. 기본 브랜치에서 작업할 수 없습니다."
    exit 1
fi

# 커밋 존재 확인
BASE_BRANCH="develop"
git rev-parse --verify origin/develop >/dev/null 2>&1 || BASE_BRANCH="main"
COMMIT_COUNT=$(git rev-list --count HEAD ^origin/${BASE_BRANCH} 2>/dev/null || echo "0")
if [ "$COMMIT_COUNT" = "0" ]; then
    echo "ERROR: No commits to push"
    post_comment "❌ 변경사항이 없습니다. 작업이 제대로 수행되지 않았을 수 있습니다."
    exit 1
fi

echo "==> Found ${COMMIT_COUNT} commit(s) to push"
echo "==> Commits:"
git log --oneline HEAD ^origin/${BASE_BRANCH}

# =============================================================================
# 커밋별 라인 코멘트 생성 (AI 분석)
# =============================================================================
echo "==> Generating commit line comments..."

# 각 커밋에 대해 반복
COMMITS=$(git log --format="%H" HEAD ^origin/${BASE_BRANCH} 2>/dev/null || echo "")
if [ -n "$COMMITS" ]; then
    for COMMIT_SHA in $COMMITS; do
        echo "==> Analyzing commit: ${COMMIT_SHA}"

        # 커밋 메시지와 diff 가져오기
        COMMIT_MSG=$(git log -1 --pretty=format:"%s" "$COMMIT_SHA")
        COMMIT_DIFF=$(git show "$COMMIT_SHA" --format="" --unified=3)

        # Claude에게 커밋 분석 요청 (간단한 프롬프트)
        ANALYSIS_PROMPT="다음 커밋을 분석하고 주요 변경사항을 3줄 이내로 요약하세요. 필요시 mermaid 다이어그램을 사용하세요.

커밋: ${COMMIT_MSG}

Diff:
${COMMIT_DIFF}

응답 형식 (마크다운):
- 변경사항 요약
- (선택) mermaid 다이어그램"

        # Claude API 호출 (타임아웃 30초)
        ANALYSIS_RESULT=$(timeout 30s curl -s --max-time 30 -X POST \
            -H "anthropic-version: 2023-06-01" \
            -H "x-api-key: ${ANTHROPIC_API_KEY}" \
            -H "Content-Type: application/json" \
            -d "$(jq -n \
                --arg model "claude-sonnet-4-20250514" \
                --arg prompt "$ANALYSIS_PROMPT" \
                '{
                    model: $model,
                    max_tokens: 512,
                    messages: [
                        {
                            role: "user",
                            content: $prompt
                        }
                    ]
                }')" \
            "https://api.anthropic.com/v1/messages" 2>/dev/null || echo "{}")

        # 응답 파싱
        COMMENT_TEXT=$(echo "$ANALYSIS_RESULT" | jq -r '.content[0].text // "변경사항 분석 실패"' 2>/dev/null || echo "변경사항 분석 실패")

        # 커밋에 코멘트 작성 (GitLab API)
        echo "==> Posting comment to commit ${COMMIT_SHA}"
        curl -s --max-time 15 -X POST \
            -H "PRIVATE-TOKEN: ${GITLAB_TOKEN}" \
            -H "Content-Type: application/json" \
            -d "$(jq -n --arg note "📝 **AI 분석**

${COMMENT_TEXT}" '{note: $note}')" \
            "${GITLAB_API}/projects/${PROJECT_ID}/repository/commits/${COMMIT_SHA}/comments" > /dev/null 2>&1 || \
            echo "Warning: Failed to post commit comment" >&2
    done
fi

# =============================================================================
# Git Push 및 MR 생성
# =============================================================================

# 변경사항이 없는지 확인 (코드 변경이 없으면 MR 생성 건너뛰기)
if [ -z "$(git diff origin/${BASE_BRANCH}...HEAD)" ]; then
    echo "==> No code changes detected, skipping MR creation"

    COMPLETION_MSG="✅ 작업이 완료되었습니다! (MR 생성 생략)

- **브랜치**: \`${BRANCH_NAME}\`
- **커밋 수**: ${COMMIT_COUNT}"
    [ "$TOKEN_USAGE" != "unknown" ] && COMPLETION_MSG="${COMPLETION_MSG}
- **토큰 사용량**: ${TOKEN_USAGE}"
    COMPLETION_MSG="${COMPLETION_MSG}

ℹ️ 코드 변경사항이 없어서 MR을 생성하지 않았습니다.
이 이슈는 코드 외적인 작업(위키 업데이트, 설정 변경 등)으로 완료되었습니다."

    post_comment "$COMPLETION_MSG"

    echo "==> Done! (No code changes, MR creation skipped)"
    exit 0
fi

echo "==> Pushing ${BRANCH_NAME}..."
git push -u origin "${BRANCH_NAME}" || {
    post_comment "❌ 브랜치 push 실패: ${BRANCH_NAME}"
    exit 1
}

# 기존 열린 MR 확인
echo "==> Checking for existing open MRs..."
OPEN_MR=$(curl -s --max-time 10 --connect-timeout 5 \
    -H "PRIVATE-TOKEN: ${GITLAB_TOKEN}" \
    "${GITLAB_API}/projects/${PROJECT_ID}/merge_requests?state=opened&source_branch=${BRANCH_NAME}" 2>/dev/null | \
    jq -r '.[0].iid // "null"')

if [ "$OPEN_MR" != "null" ] && [ -n "$OPEN_MR" ]; then
    echo "==> Found existing open MR: !${OPEN_MR}"

    MR_URL="${GITLAB_URL}/${PROJECT_PATH}/-/merge_requests/${OPEN_MR}"

    COMPLETION_MSG="✅ 작업이 완료되었습니다! (기존 MR에 커밋 추가)

- **MR**: ${MR_URL}
- **브랜치**: \`${BRANCH_NAME}\`
- **커밋 수**: ${COMMIT_COUNT}"
    [ "$TOKEN_USAGE" != "unknown" ] && COMPLETION_MSG="${COMPLETION_MSG}
- **토큰 사용량**: ${TOKEN_USAGE}"
    COMPLETION_MSG="${COMPLETION_MSG}

ℹ️ 기존 MR !${OPEN_MR}이 열려있어서 새 MR을 생성하지 않고 커밋을 추가했습니다.
변경사항을 확인하고 머지해주세요."

    post_comment "$COMPLETION_MSG"

    echo "==> Done! (Commits pushed to existing MR !${OPEN_MR})"
    exit 0
fi

# SKIP_MR_CREATION 플래그 확인
if [ "${SKIP_MR_CREATION}" = "true" ]; then
    echo "==> Skipping MR creation (SKIP_MR_CREATION=true)"

    COMPLETION_MSG="✅ 작업이 완료되었습니다! (MR 생성 생략)

- **브랜치**: \`${BRANCH_NAME}\`
- **커밋 수**: ${COMMIT_COUNT}"
    [ "$TOKEN_USAGE" != "unknown" ] && COMPLETION_MSG="${COMPLETION_MSG}
- **토큰 사용량**: ${TOKEN_USAGE}"
    COMPLETION_MSG="${COMPLETION_MSG}

⚠️ 이 이슈는 \`task\` 또는 \`no-code\` 라벨이 있어서 MR을 자동으로 생성하지 않았습니다.
필요한 경우 수동으로 MR을 생성해주세요."

    post_comment "$COMPLETION_MSG"

    echo "==> Done! (MR creation skipped)"
    exit 0
fi

# MR 생성
echo "==> Creating Merge Request..."

# 커밋 로그 수집 (MR 설명용)
COMMIT_LOG=$(git log --pretty=format:"- %s" HEAD ^origin/${BASE_BRANCH} 2>/dev/null || echo "- (커밋 로그를 가져올 수 없습니다)")

# MR 설명 생성 (커밋 내용 요약 포함)
MR_DESC="Closes #${ISSUE_IID}

이 MR은 Fluffybot이 자동 생성했습니다.

## 변경 사항
${COMMIT_LOG}

## 통계
- **커밋 수**: ${COMMIT_COUNT}"
[ "$TOKEN_USAGE" != "unknown" ] && MR_DESC="${MR_DESC}
- **토큰 사용량**: ${TOKEN_USAGE}"
MR_DESC="${MR_DESC}

---
🤖 Generated by Fluffybot"

MR_RESPONSE=$(curl -s --max-time 20 --connect-timeout 5 -X POST \
    -H "PRIVATE-TOKEN: ${GITLAB_TOKEN}" \
    -H "Content-Type: application/json" \
    -d "$(jq -n \
        --arg source "$BRANCH_NAME" \
        --arg target "$BASE_BRANCH" \
        --arg title "[Fluffybot] #${ISSUE_IID}: ${ISSUE_TITLE}" \
        --arg desc "$MR_DESC" \
        '{
            source_branch: $source,
            target_branch: $target,
            title: $title,
            description: $desc,
            remove_source_branch: true
        }')" \
    "${GITLAB_API}/projects/${PROJECT_ID}/merge_requests" 2>/dev/null || echo "{}")

MR_IID=$(echo "$MR_RESPONSE" | jq -r '.iid')
MR_URL=$(echo "$MR_RESPONSE" | jq -r '.web_url')

# 완료 코멘트 및 이슈 본문 업데이트
if [ "$MR_IID" != "null" ] && [ -n "$MR_IID" ]; then
    # 이슈 본문에 브랜치 정보 추가
    echo "==> Updating issue description with branch info..."

    # 기존 Fluffybot 섹션 제거
    UPDATED_DESCRIPTION=$(echo "$ISSUE_DESCRIPTION" | awk 'BEGIN {RS=""; ORS="\n"} /^---$/ && /🤖 \*\*Fluffybot 작업 정보\*\*/ {exit} {print}')

    # 새 Fluffybot 섹션 추가
    FLUFFYBOT_SECTION="
---
🤖 **Fluffybot 작업 정보**
- 브랜치: \`${BRANCH_NAME}\`
- MR: !${MR_IID}"

    NEW_ISSUE_DESCRIPTION="${UPDATED_DESCRIPTION}${FLUFFYBOT_SECTION}"

    # 이슈 본문 업데이트
    curl -s --max-time 20 --connect-timeout 5 -X PUT \
        -H "PRIVATE-TOKEN: ${GITLAB_TOKEN}" \
        -H "Content-Type: application/json" \
        -d "$(jq -n --arg desc "$NEW_ISSUE_DESCRIPTION" '{description: $desc}')" \
        "${GITLAB_API}/projects/${PROJECT_ID}/issues/${ISSUE_IID}" > /dev/null 2>&1 || \
        echo "Warning: Failed to update issue description" >&2

    # 작업 요약 생성
    echo "==> Generating work summary..."
    WORK_SUMMARY="## 📋 작업 요약

이 MR에서 수행한 작업은 다음과 같습니다:

### 변경 사항
${COMMIT_LOG}

### 통계
- **커밋 수**: ${COMMIT_COUNT}"
    [ "$TOKEN_USAGE" != "unknown" ] && WORK_SUMMARY="${WORK_SUMMARY}
- **토큰 사용량**: ${TOKEN_USAGE}"

    # Git diff 통계 추가
    DIFF_STATS=$(git diff --stat origin/${BASE_BRANCH}...HEAD | tail -1)
    [ -n "$DIFF_STATS" ] && WORK_SUMMARY="${WORK_SUMMARY}
- **변경 통계**: ${DIFF_STATS}"

    WORK_SUMMARY="${WORK_SUMMARY}

자세한 내용은 커밋 히스토리를 확인해주세요."

    # MR에 작업 요약 코멘트 추가
    echo "==> Posting work summary to MR..."
    curl -s --max-time 15 --connect-timeout 5 -X POST \
        -H "PRIVATE-TOKEN: ${GITLAB_TOKEN}" \
        -H "Content-Type: application/json" \
        -d "$(jq -n --arg body "$WORK_SUMMARY" '{body: $body}')" \
        "${GITLAB_API}/projects/${PROJECT_ID}/merge_requests/${MR_IID}/notes" > /dev/null 2>&1 || \
        echo "Warning: Failed to post comment to MR" >&2

    # Build completion message
    COMPLETION_MSG="✅ 작업이 완료되었습니다!

- **MR**: ${MR_URL}
- **커밋 수**: ${COMMIT_COUNT}"
    [ "$TOKEN_USAGE" != "unknown" ] && COMPLETION_MSG="${COMPLETION_MSG}
- **토큰 사용량**: ${TOKEN_USAGE}"
    COMPLETION_MSG="${COMPLETION_MSG}

변경사항을 확인하고 머지해주세요."

    # Add branch info only for new branches
    if [ -z "$EXISTING_BRANCH" ]; then
        BRANCH_MSG="🔗 **작업 브랜치**: \`${BRANCH_NAME}\`

${COMPLETION_MSG}"
        post_comment "$BRANCH_MSG"
    else
        post_comment "$COMPLETION_MSG"
    fi

    echo "==> Success! MR created: ${MR_URL}"

    # =============================================================================
    # 위키 및 CLAUDE.md 업데이트
    # =============================================================================
    echo "==> Updating project documentation..."

    # 현재 날짜 가져오기 (YYYY-MM 형식)
    CURRENT_DATE=$(date +"%Y-%m")

    # 새 변경사항 항목 생성
    NEW_ENTRY="### Issue #${ISSUE_IID}: ${ISSUE_TITLE} (${CURRENT_DATE})
- MR: !${MR_IID}
- 브랜치: \`${BRANCH_NAME}\`
- 변경 사항:
${COMMIT_LOG}
"

    # 위키 페이지 생성 함수
    create_wiki_page() {
        local title="$1"
        local content="$2"
        local slug="$3"

        echo "    - Creating wiki page: ${title}"

        curl -s --max-time 15 --connect-timeout 5 -X POST \
            -H "PRIVATE-TOKEN: ${GITLAB_TOKEN}" \
            -H "Content-Type: application/json" \
            -d "$(jq -n \
                --arg title "$title" \
                --arg content "$content" \
                '{title: $title, content: $content, format: "markdown"}')" \
            "${GITLAB_API}/projects/${PROJECT_ID}/wikis" > /dev/null 2>&1 && {
                echo "      ✓ Created: ${title}"
                return 0
            } || {
                echo "      ✗ Failed: ${title}"
                return 1
            }
    }

    # Wiki가 있는지 확인 (WIKI_COUNT는 70-78줄에서 설정됨)
    WIKI_UPDATED=false

    if [ -z "$WIKI_COUNT" ] || [ "$WIKI_COUNT" -eq 0 ]; then
        # 위키가 없으면 기본 위키 구조 생성
        echo "==> No wiki found, creating initial wiki structure..."

        # Home 페이지
        HOME_CONTENT="# ${PROJECT_PATH##*/}

이 프로젝트는 Fluffybot이 관리합니다.

## 위키 페이지

- [[Architecture]] - 아키텍처 및 기술 스택
- [[Development-Guide]] - 개발 가이드
- [[Deployment]] - 배포 방법
- [[Recent-Changes]] - 최근 변경사항

## Fluffybot 사용법

1. GitLab 이슈를 생성합니다
2. 이슈에 \`fluffybot\`을 할당합니다
3. 자동으로 작업이 수행되고 MR이 생성됩니다

또는 이슈 코멘트에서 \`@fluffybot\`을 멘션하여 질문할 수 있습니다."

        # Architecture 페이지
        ARCHITECTURE_CONTENT="# 아키텍처

## 기술 스택

작업하면서 이 섹션을 채워나갑니다.

## 주요 컴포넌트

작업하면서 이 섹션을 채워나갑니다."

        # Development-Guide 페이지
        DEVELOPMENT_CONTENT="# 개발 가이드

## 개발 환경

작업하면서 이 섹션을 채워나갑니다.

## 빌드 및 실행

작업하면서 이 섹션을 채워나갑니다."

        # Deployment 페이지
        DEPLOYMENT_CONTENT="# 배포

## 배포 방법

작업하면서 이 섹션을 채워나갑니다."

        # Recent-Changes 페이지
        RECENT_CHANGES_CONTENT="# 최근 변경사항

이 페이지는 Fluffybot이 자동으로 업데이트합니다.

## ${CURRENT_DATE}

${NEW_ENTRY}"

        # 위키 페이지들 생성
        create_wiki_page "Home" "$HOME_CONTENT" "home"
        create_wiki_page "Architecture" "$ARCHITECTURE_CONTENT" "architecture"
        create_wiki_page "Development-Guide" "$DEVELOPMENT_CONTENT" "development-guide"
        create_wiki_page "Deployment" "$DEPLOYMENT_CONTENT" "deployment"
        create_wiki_page "Recent-Changes" "$RECENT_CHANGES_CONTENT" "recent-changes" && WIKI_UPDATED=true

        if [ "$WIKI_UPDATED" = true ]; then
            post_comment "📚 프로젝트 위키가 생성되었습니다!

생성된 페이지:
- Home - 프로젝트 개요
- Architecture - 아키텍처
- Development-Guide - 개발 가이드
- Deployment - 배포 방법
- Recent-Changes - 최근 변경사항

위키를 방문하여 내용을 확인하고 필요한 정보를 추가해주세요."
        fi

    elif [ "$WIKI_COUNT" -gt 0 ]; then
        # 위키가 있으면 Recent-Changes 페이지 업데이트
        echo "==> Wiki pages found, attempting to update Recent-Changes page..."

        # Recent-Changes 페이지 조회
        RECENT_CHANGES_PAGE=$(curl -s --max-time 10 --connect-timeout 5 \
            -H "PRIVATE-TOKEN: ${GITLAB_TOKEN}" \
            "${GITLAB_API}/projects/${PROJECT_ID}/wikis/recent-changes" 2>/dev/null || echo "{}")

        # 기존 내용 가져오기
        EXISTING_CONTENT=$(echo "$RECENT_CHANGES_PAGE" | jq -r '.content // ""' 2>/dev/null || echo "")

        if [ -n "$EXISTING_CONTENT" ] && [ "$EXISTING_CONTENT" != "null" ] && [ "$EXISTING_CONTENT" != "" ]; then
            echo "==> Updating existing Recent-Changes wiki page..."

            # 기존 내용에 새 항목 추가
            UPDATED_CONTENT="${EXISTING_CONTENT}

${NEW_ENTRY}"

            # Wiki 페이지 업데이트
            curl -s --max-time 15 --connect-timeout 5 -X PUT \
                -H "PRIVATE-TOKEN: ${GITLAB_TOKEN}" \
                -H "Content-Type: application/json" \
                -d "$(jq -n --arg content "$UPDATED_CONTENT" '{content: $content, format: "markdown"}')" \
                "${GITLAB_API}/projects/${PROJECT_ID}/wikis/recent-changes" > /dev/null 2>&1 && {
                    echo "==> Recent-Changes wiki page updated successfully"
                    WIKI_UPDATED=true
                    post_comment "📝 Recent-Changes 위키 페이지가 업데이트되었습니다."
                } || {
                    echo "==> Warning: Failed to update Recent-Changes wiki page"
                }
        else
            echo "==> Recent-Changes wiki page not found, creating new one..."

            # 새 Recent-Changes 페이지 생성
            WIKI_CONTENT="# 최근 변경사항

이 페이지는 Fluffybot이 자동으로 업데이트합니다.

## ${CURRENT_DATE}

${NEW_ENTRY}"

            curl -s --max-time 15 --connect-timeout 5 -X POST \
                -H "PRIVATE-TOKEN: ${GITLAB_TOKEN}" \
                -H "Content-Type: application/json" \
                -d "$(jq -n \
                    --arg title "Recent-Changes" \
                    --arg content "$WIKI_CONTENT" \
                    '{title: $title, content: $content, format: "markdown"}')" \
                "${GITLAB_API}/projects/${PROJECT_ID}/wikis" > /dev/null 2>&1 && {
                    echo "==> Recent-Changes wiki page created successfully"
                    WIKI_UPDATED=true
                    post_comment "📝 Recent-Changes 위키 페이지가 생성되었습니다."
                } || {
                    echo "==> Warning: Failed to create Recent-Changes wiki page"
                }
        fi
    fi

    # CLAUDE.md 업데이트 (위키 업데이트 실패 시 또는 위키가 없을 때 필수)
    if [ "$WIKI_UPDATED" = false ]; then
        echo "==> Updating CLAUDE.md..."

        if [ -f "${WORK_DIR}/CLAUDE.md" ]; then
            # 임시 파일 생성
            TEMP_CLAUDE="/tmp/claude_md_update.md"

            # CLAUDE.md 읽기
            cat "${WORK_DIR}/CLAUDE.md" > "$TEMP_CLAUDE"

            # "## 최근 주요 변경사항" 섹션을 찾아서 새 항목 추가
            if grep -q "## 최근 주요 변경사항" "$TEMP_CLAUDE"; then
                # 섹션이 있으면 그 다음에 추가
                awk -v entry="$NEW_ENTRY" '
                    /## 최근 주요 변경사항/ {
                        print $0
                        if (getline > 0) {
                            print $0
                            print ""
                            print entry
                        }
                        next
                    }
                    {print}
                ' "$TEMP_CLAUDE" > "${WORK_DIR}/CLAUDE.md"
            else
                # 섹션이 없으면 파일 시작 부분에 추가
                echo "## 최근 주요 변경사항 (${CURRENT_DATE})

$NEW_ENTRY

---

" > "${WORK_DIR}/CLAUDE.md"
                cat "$TEMP_CLAUDE" >> "${WORK_DIR}/CLAUDE.md"
            fi

            # CLAUDE.md 커밋
            cd "${WORK_DIR}"
            git add CLAUDE.md
            if ! git diff --cached --quiet; then
                git commit -m "docs: CLAUDE.md 업데이트 - Issue #${ISSUE_IID} 작업 내용 기록"
                git push origin "${BRANCH_NAME}"
                echo "==> CLAUDE.md updated and pushed"

                # CLAUDE.md 업데이트 코멘트
                post_comment "📝 CLAUDE.md가 업데이트되었습니다."
            fi
        else
            echo "==> Warning: CLAUDE.md not found in project root, skipping update"
        fi
    fi
else
    ERROR_MSG=$(echo "$MR_RESPONSE" | jq -r '.message // .error // "unknown error"')
    post_comment "⚠️ 작업은 완료되었으나 MR 생성에 실패했습니다.

- **브랜치**: \`${BRANCH_NAME}\`
- **오류**: ${ERROR_MSG}

수동으로 MR을 생성해주세요."
    echo "==> Warning: MR creation failed"
fi

echo "==> Done!"