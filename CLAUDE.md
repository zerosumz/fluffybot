# CLAUDE.md

이 파일은 Claude Code(claude.ai/code)가 이 저장소에서 작업할 때 참고할 가이드입니다.

> **📖 상세 문서는 프로젝트 위키를 참고하세요.**

## 최근 주요 변경사항 (2026-01)

- initial commits

## 프로젝트 개요

Fluffybot은 GitLab 이슈에 `fluffybot`을 할당하면 Claude Code CLI를 실행하는 Kubernetes Worker Job을 생성하여 개발 작업을 자동화하는 GitLab 웹훅 서비스입니다.

### 주요 기능

- **Issue Hook**: 이슈에 fluffybot 할당 시 자동으로 작업 수행
- **Note Hook**: `@fluffybot` 멘션 시 AI가 대화형으로 응답
- **Wiki 통합**: 프로젝트 위키를 컨텍스트로 활용하여 정확한 작업 수행
- **자동 문서화**:
  - 위키가 없으면 자동으로 기본 위키 구조 생성 (Home, Architecture, Development-Guide, Deployment, Recent-Changes)
  - 작업 완료 시 Recent-Changes 위키 페이지 자동 업데이트
  - 위키가 없는 프로젝트는 CLAUDE.md에 변경사항 기록

### 기술 스택

- **Backend**: Java 17, Spring Boot 3.2 + WebFlux (Reactive)
- **Kubernetes**: fabric8 Kubernetes Client
- **AI**: Anthropic Claude API (Spring AI 통합)
- **Build**: Gradle
- **CI/CD**: GitLab CI/CD + Kaniko

## 저장소 구조

```
fluffybot/
├── src/main/java/com/esc/fluffybot/
│   ├── webhook/          # GitLab 웹훅 처리
│   ├── worker/           # Kubernetes Worker Job 관리
│   ├── gitlab/           # GitLab API 클라이언트
│   ├── anthropic/        # Anthropic API 클라이언트
│   └── config/           # Spring 설정
├── worker/
│   ├── Dockerfile        # Worker Job 이미지
│   └── entrypoint.sh     # Worker Job 진입점
├── helm/fluffybot/       # Helm 차트
├── scripts/              # 유틸리티 스크립트
│   └── init-wiki.sh      # Wiki 초기화
└── CLAUDE.md             # 이 파일
```

## 주요 컴포넌트

### 1. Webhook 서비스 (Spring Boot)
- **GitLabWebhookController**: `POST /webhook/gitlab` - 웹훅 수신
- **WorkerService**: Kubernetes Worker Job 생성 및 관리
- **NoteHookHandler**: 이슈 코멘트 처리 및 AI 응답
- **GitLabApiClient**: GitLab API 클라이언트
- **GitLabWikiClient**: GitLab Wiki API 클라이언트
- **AnthropicApiClient**: Anthropic Claude API 클라이언트

### 2. Worker Job (Kubernetes)
- 실제 작업을 수행하는 컨테이너
- `entrypoint.sh`가 프로젝트 클론, 컨텍스트 수집, Claude CLI 실행, MR 생성 등 처리
- TTL: 3600초 (1시간 후 자동 정리)

## 핵심 구현 요구사항

### WebFlux 리액티브 프로그래밍
- **절대 `.block()` 호출 금지** - 이벤트 루프 차단 방지
- `.flatMap()`, `.map()`, `.zipWith()` 등으로 작업 체이닝
- 블로킹 작업에는 `.subscribeOn(Schedulers.boundedElastic())` 사용

### 무한루프 방지
- **Issue Hook**: Worker Job 생성 전 이슈 본문에 작업 브랜치 정보 기록
- **Note Hook**: fluffybot 자신의 코멘트는 무시

### 브랜치 관리
- 이슈 본문에서 기존 브랜치 정보 파싱하여 재사용
- 없으면 새 브랜치 생성: `feature/{iid}-{desc}`, `fix/{iid}-{desc}`

## Git 컨벤션

### 브랜치 네이밍
- `feature/{issue-id}-{short-desc}` - 새 기능
- `fix/{issue-id}-{short-desc}` - 버그 수정
- `hotfix/{issue-id}-{short-desc}` - 긴급 수정

### 커밋 메시지 (Conventional Commits)
- `feat: 사용자 인증 추가`
- `fix: 웹훅 핸들러의 null pointer 해결`
- `refactor: GitLab API 로직 추출`
- `docs: 배포 지침 업데이트`
- `chore: Spring Boot 3.2.1로 업그레이드`

## 개발 명령어

```bash
# 빌드
./gradlew build

# 로컬 실행
GITLAB_TOKEN=glpat-xxx ANTHROPIC_API_KEY=sk-ant-xxx ./gradlew bootRun

# Docker 이미지 빌드
docker build -t fluffybot-webhook .
docker build -t fluffybot-worker ./worker

# Helm 차트 검증
helm lint ./helm/fluffybot
```

## 배포

### Helm 차트로 배포 (권장)

```bash
# 1. Namespace 생성
kubectl create namespace gitlab

# 2. Secrets 생성
kubectl create secret generic fluffybot-secrets -n gitlab \
  --from-literal=gitlab-token=glpat-xxxxxxxxxxxxxxxxxxxx \
  --from-literal=anthropic-api-key=sk-ant-xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx

# 3. Helm 설치
helm install fluffybot ./helm/fluffybot -n gitlab

# 4. 배포 확인
kubectl get all -n gitlab -l app.kubernetes.io/name=fluffybot
```

## 사용 예시

### Issue Hook - 자동 작업 실행

1. GitLab 이슈 생성
2. 이슈에 `fluffybot` 할당
3. 자동으로 Worker Job 생성 및 작업 수행
4. 완료 후 MR 생성 및 이슈 코멘트 작성

### Note Hook - 대화형 질문/답변

1. 이슈 코멘트에 `@fluffybot` 멘션과 함께 질문 작성
2. Fluffybot이 이슈 컨텍스트와 위키를 참고하여 응답

**예시:**
```
@fluffybot 이 이슈의 작업 브랜치는 뭐야? MR은 생성됐어?
```

## 상세 문서 (Wiki)

더 자세한 정보는 프로젝트 위키를 참고하세요:

- **Home** - 프로젝트 개요 및 시작 가이드
- **Architecture** - 시스템 아키텍처 및 기술 스택 상세 설명
- **Development-Guide** - 개발 환경 설정 및 가이드
- **Deployment** - 배포 방법 및 설정
- **API-Reference** - API 엔드포인트 및 사용법
- **Troubleshooting** - 문제 해결 가이드
- **Recent-Changes** - 최근 변경사항 및 이슈 히스토리

## 문제 해결

일반적인 문제는 Troubleshooting 위키를 참고하세요.

### 무한루프 발생 시
- 이슈 본문에 "🤖 **Fluffybot 작업 정보**" 섹션이 있으면 이미 처리 중
- fluffybot 자신의 코멘트에는 응답하지 않음

### 토큰 사용량이 너무 높을 때
- CLAUDE.md를 간결하게 유지 (현재와 같이)
- 불필요한 첨부파일 제거
- Wiki를 활용하여 상세 정보 분리

## 프로젝트 정보

Fluffybot은 GitLab과 Claude Code CLI를 연동하여 이슈 작업을 자동화하는 오픈소스 프로젝트입니다.
