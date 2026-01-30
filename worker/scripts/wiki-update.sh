#!/bin/bash
set -e

# =============================================================================
# Wiki 업데이트 모드
# MR이 머지된 후 호출되어 위키를 업데이트합니다
# =============================================================================

# 환경변수 검증
: "${GITLAB_URL:?GITLAB_URL is required}"
: "${GITLAB_TOKEN:?GITLAB_TOKEN is required}"
: "${BOT_USERNAME:?BOT_USERNAME is required}"
: "${PROJECT_ID:?PROJECT_ID is required}"
: "${PROJECT_PATH:?PROJECT_PATH is required}"
: "${MR_IID:?MR_IID is required}"
: "${ANTHROPIC_API_KEY:?ANTHROPIC_API_KEY is required}"

GITLAB_API="${GITLAB_URL}/api/v4"

echo "==> Wiki Update Mode"
echo "==> Project: ${PROJECT_PATH}"
echo "==> MR: !${MR_IID}"

# =============================================================================
# MR 정보 조회
# =============================================================================
echo "==> Fetching MR information..."

MR_DATA=$(curl -s --max-time 15 --connect-timeout 5 \
    -H "PRIVATE-TOKEN: ${GITLAB_TOKEN}" \
    "${GITLAB_API}/projects/${PROJECT_ID}/merge_requests/${MR_IID}" || echo "{}")

MR_TITLE=$(echo "$MR_DATA" | jq -r '.title // "Unknown"')
MR_DESC=$(echo "$MR_DATA" | jq -r '.description // ""')
MR_SOURCE_BRANCH=$(echo "$MR_DATA" | jq -r '.source_branch // ""')
MR_TARGET_BRANCH=$(echo "$MR_DATA" | jq -r '.target_branch // ""')
MR_STATE=$(echo "$MR_DATA" | jq -r '.state // ""')

if [ "$MR_STATE" != "merged" ]; then
    echo "==> MR is not merged (state: ${MR_STATE}), skipping wiki update"
    exit 0
fi

echo "==> MR Title: ${MR_TITLE}"
echo "==> MR Branch: ${MR_SOURCE_BRANCH} -> ${MR_TARGET_BRANCH}"

# 이슈 번호 추출 (MR 설명에서 "Closes #123" 형식)
ISSUE_IID=$(echo "$MR_DESC" | grep -oP 'Closes\s+#\K\d+' | head -1 || echo "")
[ -z "$ISSUE_IID" ] && ISSUE_IID=$(echo "$MR_TITLE" | grep -oP '#\K\d+' | head -1 || echo "")

if [ -z "$ISSUE_IID" ]; then
    echo "==> Warning: Could not extract issue IID from MR"
    ISSUE_TITLE="$MR_TITLE"
else
    echo "==> Related Issue: #${ISSUE_IID}"
    # 이슈 정보 조회
    ISSUE_DATA=$(curl -s --max-time 10 --connect-timeout 5 \
        -H "PRIVATE-TOKEN: ${GITLAB_TOKEN}" \
        "${GITLAB_API}/projects/${PROJECT_ID}/issues/${ISSUE_IID}" || echo "{}")
    ISSUE_TITLE=$(echo "$ISSUE_DATA" | jq -r '.title // ""')
    [ -z "$ISSUE_TITLE" ] && ISSUE_TITLE="$MR_TITLE"
fi

# =============================================================================
# 커밋 목록 조회
# =============================================================================
echo "==> Fetching commits..."

MR_COMMITS=$(curl -s --max-time 15 --connect-timeout 5 \
    -H "PRIVATE-TOKEN: ${GITLAB_TOKEN}" \
    "${GITLAB_API}/projects/${PROJECT_ID}/merge_requests/${MR_IID}/commits" || echo "[]")

COMMIT_COUNT=$(echo "$MR_COMMITS" | jq '. | length' 2>/dev/null || echo "0")
echo "==> Found ${COMMIT_COUNT} commit(s)"

# 커밋 로그 생성
COMMIT_LOG=""
if [ "$COMMIT_COUNT" -gt 0 ]; then
    COMMIT_LOG=$(echo "$MR_COMMITS" | jq -r '.[] | "- " + .title' 2>/dev/null || echo "")
fi

# =============================================================================
# 기존 위키 페이지 확인
# =============================================================================
echo "==> Checking for existing wiki..."

WIKI_PAGES=$(curl -s --max-time 15 --connect-timeout 5 \
    -H "PRIVATE-TOKEN: ${GITLAB_TOKEN}" \
    "${GITLAB_API}/projects/${PROJECT_ID}/wikis" 2>/dev/null || echo "[]")

WIKI_COUNT=$(echo "$WIKI_PAGES" | jq '. | length' 2>/dev/null || echo "0")
echo "==> Found ${WIKI_COUNT} wiki page(s)"

# =============================================================================
# Recent-Changes 위키 페이지 업데이트
# =============================================================================

# 현재 날짜 가져오기 (YYYY-MM 형식)
CURRENT_DATE=$(date +"%Y-%m")

# 새 변경사항 항목 생성
if [ -n "$ISSUE_IID" ]; then
    NEW_ENTRY="### Issue #${ISSUE_IID}: ${ISSUE_TITLE} (${CURRENT_DATE})
- MR: !${MR_IID}
- 브랜치: \`${MR_SOURCE_BRANCH}\`
- 변경 사항:
${COMMIT_LOG}
"
else
    NEW_ENTRY="### MR !${MR_IID}: ${MR_TITLE} (${CURRENT_DATE})
- 브랜치: \`${MR_SOURCE_BRANCH}\`
- 변경 사항:
${COMMIT_LOG}
"
fi

# 위키 페이지 생성 함수
create_wiki_page() {
    local title="$1"
    local content="$2"

    echo "    - Creating wiki page: ${title}"

    RESULT=$(curl -s --max-time 15 --connect-timeout 5 -X POST \
        -H "PRIVATE-TOKEN: ${GITLAB_TOKEN}" \
        -H "Content-Type: application/json" \
        -d "$(jq -n \
            --arg title "$title" \
            --arg content "$content" \
            '{title: $title, content: $content, format: "markdown"}')" \
        "${GITLAB_API}/projects/${PROJECT_ID}/wikis" 2>/dev/null || echo "{}")

    ERROR_MSG=$(echo "$RESULT" | jq -r '.message // ""')
    if [ -z "$ERROR_MSG" ]; then
        echo "      ✓ Created: ${title}"
        return 0
    else
        echo "      ✗ Failed: ${title} - ${ERROR_MSG}"
        return 1
    fi
}

WIKI_UPDATED=false

if [ "$WIKI_COUNT" -eq 0 ]; then
    # 위키가 없으면 기본 위키 구조 생성
    echo "==> No wiki found, creating initial wiki structure..."

    # Home 페이지
    HOME_CONTENT="# ${PROJECT_PATH##*/}

이 프로젝트는 ${BOT_USERNAME}이 관리합니다.

## 위키 페이지

- [[Architecture]] - 아키텍처 및 기술 스택
- [[Development-Guide]] - 개발 가이드
- [[Deployment]] - 배포 방법
- [[Recent-Changes]] - 최근 변경사항

## ${BOT_USERNAME} 사용법

1. GitLab 이슈를 생성합니다
2. 이슈에 \`${BOT_USERNAME}\`을 할당합니다
3. 자동으로 작업이 수행되고 MR이 생성됩니다

또는 이슈 코멘트에서 \`@${BOT_USERNAME}\`을 멘션하여 질문할 수 있습니다."

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

이 페이지는 ${BOT_USERNAME}이 자동으로 업데이트합니다.

## ${CURRENT_DATE}

${NEW_ENTRY}"

    # 위키 페이지들 생성
    create_wiki_page "Home" "$HOME_CONTENT"
    create_wiki_page "Architecture" "$ARCHITECTURE_CONTENT"
    create_wiki_page "Development-Guide" "$DEVELOPMENT_CONTENT"
    create_wiki_page "Deployment" "$DEPLOYMENT_CONTENT"
    create_wiki_page "Recent-Changes" "$RECENT_CHANGES_CONTENT" && WIKI_UPDATED=true

else
    # 위키가 있으면 Recent-Changes 페이지 업데이트
    echo "==> Updating Recent-Changes wiki page..."

    # Recent-Changes 페이지 조회
    RECENT_CHANGES_PAGE=$(curl -s --max-time 10 --connect-timeout 5 \
        -H "PRIVATE-TOKEN: ${GITLAB_TOKEN}" \
        "${GITLAB_API}/projects/${PROJECT_ID}/wikis/recent-changes" 2>/dev/null || echo "{}")

    # 기존 내용 가져오기
    EXISTING_CONTENT=$(echo "$RECENT_CHANGES_PAGE" | jq -r '.content // ""' 2>/dev/null || echo "")

    if [ -n "$EXISTING_CONTENT" ] && [ "$EXISTING_CONTENT" != "null" ]; then
        echo "==> Updating existing Recent-Changes page..."

        # 기존 내용에 새 항목 추가
        UPDATED_CONTENT="${EXISTING_CONTENT}

${NEW_ENTRY}"

        # Wiki 페이지 업데이트
        UPDATE_RESULT=$(curl -s --max-time 15 --connect-timeout 5 -X PUT \
            -H "PRIVATE-TOKEN: ${GITLAB_TOKEN}" \
            -H "Content-Type: application/json" \
            -d "$(jq -n --arg content "$UPDATED_CONTENT" '{content: $content, format: "markdown"}')" \
            "${GITLAB_API}/projects/${PROJECT_ID}/wikis/recent-changes" 2>/dev/null || echo "{}")

        ERROR_MSG=$(echo "$UPDATE_RESULT" | jq -r '.message // ""')
        if [ -z "$ERROR_MSG" ]; then
            echo "==> Recent-Changes wiki page updated successfully"
            WIKI_UPDATED=true
        else
            echo "==> Failed to update Recent-Changes: ${ERROR_MSG}"
        fi
    else
        echo "==> Recent-Changes page not found, creating new one..."

        # 새 Recent-Changes 페이지 생성
        WIKI_CONTENT="# 최근 변경사항

이 페이지는 ${BOT_USERNAME}이 자동으로 업데이트합니다.

## ${CURRENT_DATE}

${NEW_ENTRY}"

        create_wiki_page "Recent-Changes" "$WIKI_CONTENT" && WIKI_UPDATED=true
    fi
fi

# =============================================================================
# MR에 완료 코멘트 작성
# =============================================================================

if [ "$WIKI_UPDATED" = true ]; then
    WIKI_COMMENT="📚 **위키 업데이트 완료**

### 수정된 페이지
- [[Recent-Changes]] - 이번 MR 변경사항 추가

### 변경 요약
- 커밋 ${COMMIT_COUNT}개 반영
- 주요 변경: MR !${MR_IID} 병합 내역 기록

---
🤖 Generated by ${BOT_USERNAME}"

    echo "==> Posting success comment to MR..."
    curl -s --max-time 15 --connect-timeout 5 -X POST \
        -H "PRIVATE-TOKEN: ${GITLAB_TOKEN}" \
        -H "Content-Type: application/json" \
        -d "$(jq -n --arg body "$WIKI_COMMENT" '{body: $body}')" \
        "${GITLAB_API}/projects/${PROJECT_ID}/merge_requests/${MR_IID}/notes" > /dev/null 2>&1 || \
        echo "Warning: Failed to post comment to MR" >&2

    echo "==> Wiki update completed successfully"
else
    ERROR_COMMENT="⚠️ **위키 업데이트 실패**

위키 페이지 업데이트에 실패했습니다. 수동으로 Recent-Changes 페이지를 확인해주세요.

---
🤖 Generated by ${BOT_USERNAME}"

    echo "==> Posting failure comment to MR..."
    curl -s --max-time 15 --connect-timeout 5 -X POST \
        -H "PRIVATE-TOKEN: ${GITLAB_TOKEN}" \
        -H "Content-Type: application/json" \
        -d "$(jq -n --arg body "$ERROR_COMMENT" '{body: $body}')" \
        "${GITLAB_API}/projects/${PROJECT_ID}/merge_requests/${MR_IID}/notes" > /dev/null 2>&1 || \
        echo "Warning: Failed to post comment to MR" >&2

    echo "==> Wiki update failed"
    exit 1
fi

echo "==> Done!"
