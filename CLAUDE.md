# CLAUDE.md

이 파일은 Claude Code가 이 저장소에서 작업할 때 참고할 가이드입니다.

> **📖 상세 문서는 [프로젝트 위키](https://gitlab.esc-bot.com/esc/fluffybot/-/wikis/home)를 참고하세요.**

## 프로젝트 개요

Fluffybot은 GitLab 이슈/MR에서 `@fluffybot` 멘션 시 AI가 자동으로 응답하거나 코드 작업을 수행하는 Kubernetes 네이티브 AI Teammate입니다.

### 핵심 기능

- **Note Hook**: `@fluffybot` 멘션으로 대화형 AI 응답
- **Issue Hook**: fluffybot 할당 시 자동 코드 작업 수행
- **Wiki 통합**: 프로젝트 위키를 컨텍스트로 활용
- **자동 문서화**: MR 머지 시 Recent-Changes 위키 자동 업데이트

### 기술 스택

Java 17, Spring Boot 3.2 WebFlux, Kubernetes, Anthropic Claude API, Gradle

## 아키텍처

```
GitLab Event (@fluffybot)
    ↓
[Webhook Service] → [Note Hook: AI 응답] → 코멘트 작성
    ↓
[Worker Job 생성] → clone → wiki → claude → commit → MR
    ↓
[TTL 1시간 후 자동 정리]
```

## 주요 디렉토리

- `src/main/java/com/esc/fluffybot/` - Spring Boot 애플리케이션
  - `webhook/` - 웹훅 수신 및 처리
  - `worker/` - Kubernetes Job 관리
  - `gitlab/` - GitLab API 클라이언트 (API, Wiki)
  - `anthropic/` - Anthropic API 클라이언트
- `worker/` - Worker Job 컨테이너
  - `entrypoint.sh` - 메인 진입점
  - `issue-work.sh` - 이슈 작업 처리
  - `wiki-update.sh` - Wiki 업데이트
- `helm/fluffybot/` - Helm 차트

## 핵심 규칙

### WebFlux 리액티브
- **절대 `.block()` 금지** (이벤트 루프 차단)
- `.flatMap()`, `.map()` 등으로 체이닝
- 블로킹 작업: `.subscribeOn(Schedulers.boundedElastic())`

### 무한루프 방지
- Issue Hook: 이슈 본문의 "🤖 Fluffybot 작업 정보" 확인
- Note Hook: fluffybot 자신의 코멘트 무시

### 브랜치 관리
- 기존 브랜치 재사용 (이슈 본문 파싱)
- 신규: `feature/{iid}-{desc}`, `fix/{iid}-{desc}`

## Git 컨벤션

**브랜치**: `feature/{iid}-{desc}`, `fix/{iid}-{desc}`, `hotfix/{iid}-{desc}`

**커밋 메시지** (Conventional Commits):
```
feat: 사용자 인증 추가
fix: 웹훅 핸들러 null pointer 해결
refactor: GitLab API 로직 추출
docs: 배포 지침 업데이트
```

## 빠른 명령어

```bash
# 빌드 및 실행
./gradlew build
GITLAB_TOKEN=xxx ANTHROPIC_API_KEY=xxx ./gradlew bootRun

# 배포
helm install fluffybot ./helm/fluffybot -n gitlab
```

## 상세 문서

**Wiki**: https://gitlab.esc-bot.com/esc/fluffybot/-/wikis/home

- Architecture - 시스템 아키텍처
- Development-Guide - 개발 가이드
- Deployment - 배포 방법
- API-Reference - API 문서
- Troubleshooting - 문제 해결
- Recent-Changes - 최근 변경사항
