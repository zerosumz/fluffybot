# 브랜치명 생성 개선

## 문제점

기존 브랜치명 생성 로직은 한글 이슈 제목을 제대로 처리하지 못했습니다:

```bash
# 기존 로직
BRANCH_NAME="${BRANCH_PREFIX}/${ISSUE_IID}-$(echo "$ISSUE_TITLE" | tr '[:upper:]' '[:lower:]' | tr -cs 'a-z0-9' '-' | head -c 30)"
```

### 예시

| 이슈 제목 | 기존 브랜치명 | 문제점 |
|----------|--------------|--------|
| "로그인 기능 추가" | `feature/7--` | 한글이 모두 제거되어 빈 slug |
| "사용자 인증 버그 수정" | `fix/12--` | 의미 없는 브랜치명 |
| "API 응답 속도 개선" | `feature/15--` | 브랜치명만으로 작업 내용 파악 불가 |

## 해결 방법

Claude API를 사용하여 한글 이슈 제목을 영문 slug로 자동 변환합니다.

### 새로운 로직

1. **translate_to_slug()** 함수 추가:
   - 한글 제목을 Claude API에 전송
   - 간결한 영문 slug로 변환 (최대 3-4 단어)
   - ASCII 전용 제목은 단순 변환 (API 호출 생략)
   - 변환 실패 시 fallback: `issue-{IID}`

2. **브랜치명 생성 개선**:
   ```bash
   ISSUE_SLUG=$(translate_to_slug "$ISSUE_TITLE")
   BRANCH_NAME="${BRANCH_PREFIX}/${ISSUE_IID}-${ISSUE_SLUG}"
   ```

### 예시

| 이슈 제목 | 개선된 브랜치명 | 장점 |
|----------|----------------|------|
| "로그인 기능 추가" | `feature/7-add-login` | 명확한 작업 내용 |
| "사용자 인증 버그 수정" | `fix/12-fix-user-auth` | 버그 수정 대상 파악 가능 |
| "API 응답 속도 개선" | `feature/15-improve-api-speed` | 개선 목적 명확 |
| "브랜치명 생성 개선" | `feature/18-improve-branch-naming` | 자기 참조 😊 |

## 기술 사양

### API 호출

```bash
curl -X POST \
  -H "anthropic-version: 2023-06-01" \
  -H "x-api-key: ${ANTHROPIC_API_KEY}" \
  -H "Content-Type: application/json" \
  -d '{
    "model": "claude-sonnet-4-20250514",
    "max_tokens": 50,
    "messages": [{
      "role": "user",
      "content": "다음 한글 이슈 제목을 간결한 영문 slug로 변환하세요..."
    }]
  }' \
  "https://api.anthropic.com/v1/messages"
```

### 변환 규칙

- 소문자만 사용
- 단어는 하이픈(-)으로 구분
- 최대 3-4단어
- 불필요한 조사 제거
- 핵심 의미만 추출

### 안전장치

1. **타임아웃**: 15초 (API 호출이 오래 걸릴 경우 대비)
2. **Fallback**: 변환 실패 시 `issue-{IID}` 사용
3. **ASCII 최적화**: 이미 영문인 경우 API 호출 생략

## 테스트 결과

```bash
$ translate_to_slug "브랜치명 생성 개선"
improve-branch-naming

$ translate_to_slug "Login Feature"
login-feature
```

## 파일 변경 사항

- `worker/scripts/issue-work.sh`:
  - `translate_to_slug()` 함수 추가 (64줄)
  - 브랜치명 생성 로직 수정 (7줄)

## 영향도

- **Worker Job**: 새 브랜치 생성 시에만 API 호출 (기존 브랜치 재사용 시 영향 없음)
- **API 비용**: 최대 50 토큰 (약 0.001 USD per call)
- **성능**: 약 1-2초 추가 (브랜치 생성 시에만)

## 향후 개선 사항

1. 브랜치명 캐싱 (동일한 제목 재사용 시 API 호출 생략)
2. 로컬 번역 모델 사용 (API 비용 절감)
3. 사용자 정의 slug 지원 (이슈 라벨 활용)
