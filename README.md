# Fluffybot - AI Teammate for GitLab

![](fluffybot.jpg)

GitLab 이슈에서 `@fluffybot`을 멘션하면 Claude Code CLI를 실행하여 자동으로 작업을 수행하는 AI Teammate입니다.

## 주요 기능

- 🤖 **자동 이슈 처리**: 이슈에 fluffybot을 할당하면 자동으로 코드 작성/수정
- 💬 **대화형 AI 응답**: `@fluffybot` 멘션으로 질문하고 답변 받기
- 📚 **위키 통합**: 프로젝트 위키를 자동으로 생성하고 컨텍스트로 활용
- 🔄 **자동 MR 생성**: 작업 완료 시 Merge Request 자동 생성
- 📝 **자동 문서화**: MR 머지 시 Recent-Changes 위키 페이지 자동 업데이트
- ⚡ **Kubernetes 네이티브**: Kubernetes Job으로 격리된 환경에서 실행

## 요구사항

- Kubernetes 클러스터 (1.19+)
- GitLab 인스턴스 (14.0+)
- Anthropic API Key (Claude API)
- Container Registry (Docker Hub, GitLab Container Registry 등)

## 빠른 시작

### 1. 이미지 빌드 및 푸시

```bash
# Gradle 빌드
./gradlew build

# Docker 이미지 빌드
docker build -t your-registry/fluffybot/webhook:latest .
docker build -t your-registry/fluffybot/worker:latest ./worker

# 이미지 푸시
docker push your-registry/fluffybot/webhook:latest
docker push your-registry/fluffybot/worker:latest
```

### 2. Helm 차트로 배포

```bash
# Namespace 생성
kubectl create namespace gitlab

# Secrets 생성
kubectl create secret generic fluffybot-secrets -n gitlab \
  --from-literal=gitlab-token=glpat-xxxxxxxxxxxxxxxxxxxx \
  --from-literal=anthropic-api-key=sk-ant-xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx

# values.yaml 설정
cp helm/fluffybot/values.yaml.example helm/fluffybot/values.yaml
# values.yaml 파일을 편집하여 GitLab URL, 이미지 레지스트리 등 설정

# Helm 설치
helm install fluffybot ./helm/fluffybot -n gitlab -f helm/fluffybot/values.yaml

# 배포 확인
kubectl get all -n gitlab -l app.kubernetes.io/name=fluffybot
```

### 3. GitLab 웹훅 설정

1. GitLab 프로젝트 Settings → Webhooks
2. URL: `https://your-fluffybot-domain.com/webhook/gitlab`
3. Trigger 설정:
   - ☑ Comments
   - ☑ Issues events
   - ☑ Merge request events

### 4. 사용하기

- 이슈에 `@fluffybot` 멘션과 함께 질문하거나 작업 요청
- 이슈에 fluffybot을 할당하여 자동 작업 실행

## 아키텍처

### 시스템 구조

```
GitLab Webhook (@fluffybot 멘션/할당)
        ↓
[fluffybot-webhook] ──fabric8──→ [Worker Job]
   (Deployment)                    (임시 Job)
        ↓                               ↓
   [NoteHookHandler]               entrypoint.sh
   AI 대화형 응답                       ↓
        ↓                          clone → wiki context
   코멘트 작성                          ↓
                                claude -p "{prompt}"
                                       ↓
                                commit → push → MR
                                       ↓
                              Job 완료 (TTL: 1시간)
```

### 디렉토리 구조

```
fluffybot/
├── src/main/java/com/esc/fluffybot/
│   ├── webhook/          # GitLab 웹훅 처리
│   │   ├── controller/   # GitLabWebhookController
│   │   ├── handler/      # NoteHookHandler, MergeRequestNoteHandler
│   │   └── service/      # WebhookValidationService
│   ├── worker/           # Kubernetes Worker Job 관리
│   │   └── service/      # WorkerService, JobStatusService
│   ├── gitlab/           # GitLab API 클라이언트
│   │   ├── client/       # GitLabApiClient, GitLabWikiClient
│   │   └── dto/          # DTO 클래스
│   ├── anthropic/        # Anthropic API 클라이언트
│   │   └── client/       # AnthropicApiClient
│   └── config/           # Spring 설정
├── worker/
│   ├── Dockerfile        # Worker Job 이미지
│   ├── entrypoint.sh     # Worker Job 메인 진입점
│   ├── issue-work.sh     # 이슈 작업 처리 스크립트
│   └── wiki-update.sh    # Wiki 업데이트 스크립트
├── helm/fluffybot/       # Helm 차트
│   ├── templates/        # Kubernetes 리소스 템플릿
│   └── values.yaml       # 설정 값
├── scripts/              # 유틸리티 스크립트
│   └── init-wiki.sh      # Wiki 초기화
└── CLAUDE.md             # Claude Code 가이드
```

## 사용 방법

### 대화형 AI 응답 (Note Hook)

이슈 또는 MR 코멘트에 `@fluffybot`을 멘션하여 질문하거나 요청하세요.

**예시:**
```
@fluffybot 이 이슈의 작업 브랜치는 뭐야? MR은 생성됐어?
@fluffybot Architecture 문서를 업데이트해줘
@fluffybot 이 코드의 성능을 개선할 방법을 알려줘
```

### 자동 작업 실행 (Issue Hook)

이슈에 `fluffybot` 사용자를 할당하면 자동으로 작업을 수행합니다.

1. GitLab에서 이슈 생성
2. 이슈 설명에 작업 내용 작성
3. Assignee에 `fluffybot` 추가
4. 자동으로 Worker Job 생성 및 작업 수행
5. 작업 완료 후 MR 생성 및 이슈 코멘트 작성

### 자동 Wiki 업데이트

MR이 머지되면 자동으로 Recent-Changes 위키 페이지가 업데이트됩니다.

- 위키가 없는 프로젝트는 자동으로 기본 Wiki 페이지 생성
- 작업 내용이 Recent-Changes 페이지에 기록됨

## API 엔드포인트

| Method | Path | 설명 |
|--------|------|------|
| POST | /webhook/gitlab | GitLab 웹훅 수신 (Issue, Note, MR) |
| GET | /jobs | 실행 중인 Worker Job 목록 |
| GET | /jobs/{name} | Worker Job 상태 조회 |
| GET | /jobs/{name}/logs | Worker Job 로그 조회 |
| GET | /actuator/health | 헬스체크 |

## 개발 가이드

### 로컬 개발 환경 설정

```bash
# 환경 변수 설정
export GITLAB_URL=https://gitlab.example.com
export GITLAB_TOKEN=glpat-xxxxxxxxxxxxxxxxxxxx
export GITLAB_BOT_USERNAME=fluffybot
export ANTHROPIC_API_KEY=sk-ant-xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
export WORKER_IMAGE=registry.example.com/org/fluffybot/worker:latest
export WORKER_NAMESPACE=gitlab

# 애플리케이션 빌드 및 실행
./gradlew build
./gradlew bootRun
```

### CI/CD

GitLab CI/CD 파이프라인이 자동으로 이미지를 빌드하고 푸시합니다.

**파이프라인 구조:**
```
main 브랜치 push
    ↓
[build:webhook | build:worker] (병렬 빌드)
    ↓
[push:webhook | push:worker] (병렬 푸시)
```

**생성되는 이미지:**
- `${CI_REGISTRY_IMAGE}/webhook:latest`
- `${CI_REGISTRY_IMAGE}/webhook:${CI_COMMIT_SHORT_SHA}`
- `${CI_REGISTRY_IMAGE}/worker:latest`
- `${CI_REGISTRY_IMAGE}/worker:${CI_COMMIT_SHORT_SHA}`

## 배포 방법

### Helm 차트로 배포 (권장)

#### 1. 기본 설치

```bash
# Namespace 생성
kubectl create namespace gitlab

# Secrets 생성
kubectl create secret generic fluffybot-secrets -n gitlab \
  --from-literal=gitlab-token=glpat-xxxxxxxxxxxxxxxxxxxx \
  --from-literal=anthropic-api-key=sk-ant-xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx

# Registry pull secret 생성 (private registry 사용 시)
kubectl create secret docker-registry fluffy-registry-secret -n gitlab \
  --docker-server=registry.example.com \
  --docker-username=YOUR_USERNAME \
  --docker-password=YOUR_PASSWORD

# values.yaml 설정
cp helm/fluffybot/values.yaml.example helm/fluffybot/values.yaml
# values.yaml을 편집하여 GitLab URL, 이미지 레지스트리 등을 설정

# Helm 설치
helm install fluffybot ./helm/fluffybot -n gitlab -f helm/fluffybot/values.yaml

# 배포 확인
kubectl get all -n gitlab -l app.kubernetes.io/name=fluffybot
kubectl logs -n gitlab -l app=fluffybot-webhook -f
```

#### 2. 커스텀 설정으로 설치

```bash
helm install fluffybot ./helm/fluffybot -n gitlab \
  --set gitlab.url=https://gitlab.example.com \
  --set ingress.host=fluffybot.example.com \
  --set image.registry=registry.example.com/org/fluffybot \
  --set image.webhookTag=v1.0.0 \
  --set image.workerTag=v1.0.0
```

#### 3. 업그레이드 및 관리

```bash
# 업그레이드
helm upgrade fluffybot ./helm/fluffybot -n gitlab -f helm/fluffybot/values.yaml

# 상태 확인
helm status fluffybot -n gitlab

# 히스토리 확인
helm history fluffybot -n gitlab

# 롤백
helm rollback fluffybot -n gitlab

# 제거
helm uninstall fluffybot -n gitlab
```

### 설정 커스터마이징

`custom-values.yaml` 파일을 생성하여 설정을 오버라이드할 수 있습니다.

**필수 설정 항목:**
- `gitlab.url`: GitLab 인스턴스 URL
- `image.registry`: 이미지 레지스트리 경로
- `ingress.host`: Ingress 호스트명

**예시:**

```yaml
gitlab:
  url: https://gitlab.example.com

image:
  registry: registry.example.com/org/fluffybot
  webhookTag: v1.2.3
  workerTag: v1.2.3

webhook:
  replicas: 2
  resources:
    limits:
      cpu: 2000m
      memory: 2Gi

worker:
  timeoutMinutes: 60
  resources:
    limits:
      cpu: "4"
      memory: 8Gi

ingress:
  host: fluffybot.example.com
  tls:
    enabled: true
```

## 기술 스택

- **Backend**: Java 17, Spring Boot 3.2 + WebFlux (Reactive)
- **Kubernetes**: fabric8 Kubernetes Client
- **AI**: Anthropic Claude API (Spring AI 통합)
- **Build**: Gradle
- **CI/CD**: GitLab CI/CD + Kaniko

## 주요 컴포넌트

### Webhook 서비스
- **GitLabWebhookController**: GitLab 웹훅 수신 및 라우팅
- **NoteHookHandler**: 이슈/MR 코멘트 처리 및 AI 응답
- **MergeRequestNoteHandler**: MR 라인 코멘트 처리
- **WorkerService**: Kubernetes Worker Job 생성 및 관리
- **GitLabApiClient**: GitLab API 클라이언트
- **GitLabWikiClient**: GitLab Wiki API 클라이언트
- **AnthropicApiClient**: Anthropic Claude API 클라이언트

### Worker Job
- **entrypoint.sh**: 메인 진입점 및 모드 분기
- **issue-work.sh**: 이슈 작업 처리 (프로젝트 클론, 컨텍스트 수집, Claude 실행, MR 생성)
- **wiki-update.sh**: Wiki 업데이트 처리 (Recent-Changes 페이지 업데이트)
- TTL: 3600초 (1시간 후 자동 정리)
- BackoffLimit: 0 (재시도 없음)

## 문서

더 자세한 정보는 프로젝트 위키를 참고하세요:

- **[Home](https://gitlab.esc-bot.com/esc/fluffybot/-/wikis/home)** - 프로젝트 개요 및 시작 가이드
- **[Architecture](https://gitlab.esc-bot.com/esc/fluffybot/-/wikis/Architecture)** - 시스템 아키텍처 상세 설명
- **[Development-Guide](https://gitlab.esc-bot.com/esc/fluffybot/-/wikis/Development-Guide)** - 개발 환경 설정
- **[Deployment](https://gitlab.esc-bot.com/esc/fluffybot/-/wikis/Deployment)** - 배포 방법
- **[API-Reference](https://gitlab.esc-bot.com/esc/fluffybot/-/wikis/API-Reference)** - API 엔드포인트
- **[Troubleshooting](https://gitlab.esc-bot.com/esc/fluffybot/-/wikis/Troubleshooting)** - 문제 해결 가이드
- **[Recent-Changes](https://gitlab.esc-bot.com/esc/fluffybot/-/wikis/Recent-Changes)** - 최근 변경사항

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

## License

This project is licensed under the MIT License.

## Acknowledgments

- Powered by [Claude Code CLI](https://claude.ai/code)
- Built with [Anthropic Claude API](https://www.anthropic.com)
