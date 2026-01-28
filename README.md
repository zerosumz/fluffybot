# Fluffybot - AI Teammate for GitLab

GitLab 이슈에서 `@fluffybot`을 멘션하면 Claude Code CLI를 실행하여 자동으로 작업을 수행하는 AI Teammate.

## Features

- 🤖 **자동 이슈 처리**: 이슈에 fluffybot을 할당하면 자동으로 코드 작성/수정
- 💬 **대화형 AI 응답**: `@fluffybot` 멘션으로 질문하고 답변 받기
- 📚 **위키 통합**: 프로젝트 위키를 자동으로 생성하고 컨텍스트로 활용
- 🔄 **자동 MR 생성**: 작업 완료 시 Merge Request 자동 생성
- 📝 **자동 문서화**: Recent-Changes 위키 페이지 자동 업데이트
- ⚡ **Kubernetes 네이티브**: Kubernetes Job으로 격리된 환경에서 실행

## Requirements

- Kubernetes 클러스터
- GitLab 인스턴스
- Anthropic API Key (Claude API)
- Container Registry (Docker Hub, GitLab Container Registry 등)

## Quick Start

1. **설정 파일 준비**
   ```bash
   cp helm/fluffybot/values.yaml.example helm/fluffybot/values.yaml
   # values.yaml 편집: GitLab URL, 이미지 레지스트리 등 설정
   ```

2. **이미지 빌드 및 푸시**
   ```bash
   ./gradlew build
   docker build -t your-registry/fluffybot/webhook:latest .
   docker build -t your-registry/fluffybot/worker:latest ./worker
   docker push your-registry/fluffybot/webhook:latest
   docker push your-registry/fluffybot/worker:latest
   ```

3. **Kubernetes 배포**
   ```bash
   kubectl create namespace gitlab
   kubectl create secret generic fluffybot-secrets -n gitlab \
     --from-literal=gitlab-token=glpat-xxx \
     --from-literal=anthropic-api-key=sk-ant-xxx
   helm install fluffybot ./helm/fluffybot -n gitlab -f helm/fluffybot/values.yaml
   ```

4. **GitLab 웹훅 설정**
   - Project Settings → Webhooks
   - URL: `https://your-fluffybot-domain.com/webhook/gitlab`
   - Trigger: ☑ Comments

5. **사용하기**
   - 이슈에 `@fluffybot` 멘션으로 질문하거나 작업 요청

## 구조

```
fluffybot/
├── src/main/java/com/esc/fluffybot/
│   ├── FluffybotApplication.java
│   ├── config/
│   │   ├── GitLabProperties.java
│   │   ├── KubernetesConfig.java
│   │   ├── WebClientConfig.java
│   │   └── WorkerProperties.java
│   ├── gitlab/
│   │   ├── client/
│   │   │   └── GitLabApiClient.java
│   │   ├── dto/
│   │   │   ├── CreateMergeRequestRequest.java
│   │   │   └── CreateNoteRequest.java
│   │   └── exception/
│   │       └── GitLabApiException.java
│   ├── webhook/
│   │   ├── controller/
│   │   │   └── GitLabWebhookController.java
│   │   ├── dto/
│   │   │   ├── GitLabWebhookPayload.java
│   │   │   ├── IssueInfo.java
│   │   │   ├── ObjectAttributes.java
│   │   │   ├── ProjectInfo.java
│   │   │   └── WebhookResponse.java
│   │   └── service/
│   │       └── WebhookValidationService.java
│   └── worker/
│       ├── controller/
│       │   └── JobStatusController.java
│       ├── dto/
│       │   └── JobStatusResponse.java
│       ├── exception/
│       │   └── PodCreationException.java
│       ├── model/
│       │   └── WorkerTask.java
│       └── service/
│           ├── JobStatusService.java
│           └── WorkerService.java
├── src/main/resources/
│   └── application.yml
├── worker/
│   ├── Dockerfile
│   └── entrypoint.sh
├── k8s/
│   ├── deployment.yaml
│   ├── rbac.yaml
│   └── secret.yaml
├── sample-project/
│   ├── CLAUDE.md
│   ├── docker-compose.test.yml
│   └── db/
├── CLAUDE.md
├── Dockerfile
├── build.gradle
├── settings.gradle
└── gradle.properties
```

## 흐름

```
GitLab Webhook (@fluffybot 멘션)
        ↓
[fluffybot-webhook] ──fabric8──→ [Worker Job 생성]
      (상주)                         (임시)
                                       ↓
                                  entrypoint.sh
                                       ↓
                              clone → claude -p → push → MR
                                       ↓
                              Job 완료 (1시간 후 자동 삭제)
```

## API 엔드포인트

| Method | Path | 설명 |
|--------|------|------|
| POST | /webhook/gitlab | GitLab 웹훅 수신 |
| GET | /jobs | 실행 중인 Job 목록 |
| GET | /jobs/{name} | Job 상태 조회 |
| GET | /jobs/{name}/logs | Job 로그 조회 |
| GET | /actuator/health | 헬스체크 |

## 사용법

1. GitLab 프로젝트 루트에 `CLAUDE.md` 추가 (sample-project 참고)
2. 프로젝트/그룹 Settings → Webhooks 등록
   - URL: `https://your-fluffybot-domain.com/webhook/gitlab`
   - Trigger: ☑ Comments
3. 이슈에서 `@fluffybot 로그인 기능 만들어줘` 식으로 멘션

## CI/CD

GitLab CI/CD 파이프라인이 자동으로 이미지를 빌드하고 푸시합니다.

### 파이프라인 구조

```
main 브랜치 push
    ↓
┌──────────────┬──────────────┐
│ build:webhook│ build:worker │  (병렬 빌드)
└──────────────┴──────────────┘
    ↓
┌──────────────┬──────────────┐
│ push:webhook │ push:worker  │  (병렬 푸시)
└──────────────┴──────────────┘
```

### 생성되는 이미지

- `${CI_REGISTRY_IMAGE}/webhook:latest`
- `${CI_REGISTRY_IMAGE}/webhook:${CI_COMMIT_SHORT_SHA}`
- `${CI_REGISTRY_IMAGE}/worker:latest`
- `${CI_REGISTRY_IMAGE}/worker:${CI_COMMIT_SHORT_SHA}`

### 수동 빌드 (로컬)

```bash
# Gradle 빌드
./gradlew build

# 이미지 빌드 & 푸시
docker build -t registry.example.com/your-org/fluffybot/webhook:latest .
docker build -t registry.example.com/your-org/fluffybot/worker:latest ./worker
docker push registry.example.com/your-org/fluffybot/webhook:latest
docker push registry.example.com/your-org/fluffybot/worker:latest
```

## 배포

### Helm 차트로 배포 (권장)

```bash
# 0. values.yaml 설정
cp helm/fluffybot/values.yaml.example helm/fluffybot/values.yaml
# values.yaml을 편집하여 GitLab URL, 이미지 레지스트리 등을 설정

# 1. Namespace 생성
kubectl create namespace gitlab

# 2. 시크릿 생성
kubectl create secret generic fluffybot-secrets -n gitlab \
  --from-literal=gitlab-token=glpat-xxxxxxxxxxxxxxxxxxxx \
  --from-literal=anthropic-api-key=sk-ant-xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx

# 3. Registry pull secret 생성 (private registry 사용 시)
kubectl create secret docker-registry fluffy-registry-secret -n gitlab \
  --docker-server=registry.example.com \
  --docker-username=YOUR_USERNAME \
  --docker-password=YOUR_PASSWORD

# 4. Helm 설치
helm install fluffybot ./helm/fluffybot -n gitlab -f helm/fluffybot/values.yaml

# 커스텀 설정으로 설치
helm install fluffybot ./helm/fluffybot -n gitlab \
  --set gitlab.url=https://gitlab.example.com \
  --set ingress.host=fluffybot.example.com \
  --set image.registry=registry.example.com/org/fluffybot \
  --set image.webhookTag=v1.0.0 \
  --set image.workerTag=v1.0.0

# 5. 배포 확인
kubectl get all -n gitlab -l app.kubernetes.io/name=fluffybot
kubectl logs -n gitlab -l app=fluffybot-webhook -f
```

### Helm 차트 업그레이드

```bash
# 설정 변경 후 업그레이드
helm upgrade fluffybot ./helm/fluffybot -n gitlab \
  --set image.webhookTag=v1.1.0 \
  --set image.workerTag=v1.1.0

# 전체 values 파일로 업그레이드
helm upgrade fluffybot ./helm/fluffybot -n gitlab -f custom-values.yaml

# 배포 상태 확인
helm status fluffybot -n gitlab

# 히스토리 확인
helm history fluffybot -n gitlab

# 롤백
helm rollback fluffybot -n gitlab
```

### Helm 차트 제거

```bash
helm uninstall fluffybot -n gitlab

# 시크릿도 함께 제거
kubectl delete secret fluffybot-secrets -n gitlab
kubectl delete secret fluffy-registry-secret -n gitlab
```

### kubectl로 직접 배포

```bash
# 1. 시크릿 생성 (위와 동일)
kubectl create secret generic fluffybot-secrets -n gitlab \
  --from-literal=gitlab-token=glpat-xxxx \
  --from-literal=anthropic-api-key=sk-ant-xxxx

# 2. RBAC 설정
kubectl apply -f k8s/rbac.yaml

# 3. Webhook 서비스 배포
kubectl apply -f k8s/deployment.yaml
```

## Helm 차트 커스터마이징

`helm/fluffybot/values.yaml.example`을 복사하여 `values.yaml`을 생성하고 수정하거나, 별도의 `custom-values.yaml`을 생성하여 설정을 오버라이드할 수 있습니다.

### 필수 설정

다음 값들은 반드시 설정해야 합니다:

- `gitlab.url`: GitLab 인스턴스 URL
- `image.registry`: 이미지 레지스트리 경로
- `ingress.host`: Ingress 호스트명

### 예시: custom-values.yaml

```yaml
# GitLab URL 변경
gitlab:
  url: https://gitlab.example.com

# 이미지 태그 고정
image:
  registry: registry.example.com/org/fluffybot
  webhookTag: v1.2.3
  workerTag: v1.2.3

# Webhook 리소스 증가
webhook:
  replicas: 2
  resources:
    requests:
      cpu: 1000m
      memory: 2Gi
    limits:
      cpu: 2000m
      memory: 2Gi

# Worker Job 타임아웃 증가
worker:
  timeoutMinutes: 60
  resources:
    limits:
      cpu: "4"
      memory: 8Gi

# Ingress 도메인 변경
ingress:
  host: fluffybot.example.com
  annotations:
    cert-manager.io/cluster-issuer: letsencrypt-staging
```

설치:
```bash
helm install fluffybot ./helm/fluffybot -n gitlab -f custom-values.yaml
```

## 개발

### 환경 변수 설정 (필수)

```bash
export GITLAB_URL=https://gitlab.example.com
export GITLAB_TOKEN=glpat-xxxxxxxxxxxxxxxxxxxx
export GITLAB_BOT_USERNAME=fluffybot
export ANTHROPIC_API_KEY=sk-ant-xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
export WORKER_IMAGE=registry.example.com/your-org/fluffybot/worker:latest
export WORKER_NAMESPACE=gitlab
```

### 로컬 실행

```bash
./gradlew build
./gradlew bootRun
```

## Worker Job 설정

- `ttlSecondsAfterFinished: 3600` (1시간 후 자동 정리)
- `backoffLimit: 0` (재시도 없음)
- `restartPolicy: Never`
- Job 이름: `fluffybot-{project}-{issue-iid}-{timestamp}`

## Architecture

```
GitLab Webhook (@fluffybot mention)
        ↓
[fluffybot-webhook] ──fabric8──→ [Worker Job]
   (persistent)                    (temporary)
                                        ↓
                                  entrypoint.sh
                                        ↓
                               clone → claude → push → MR
                                        ↓
                              Job cleanup (1 hour TTL)
```

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

## License

This project is licensed under the MIT License - see the LICENSE file for details.

## Acknowledgments

- Powered by [Claude Code CLI](https://claude.ai/code)
- Built with [Anthropic Claude API](https://www.anthropic.com)
