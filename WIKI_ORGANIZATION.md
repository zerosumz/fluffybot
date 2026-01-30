# Fluffybot Wiki 구조 및 관리 가이드

이 문서는 Fluffybot 프로젝트의 GitLab Wiki 구조와 각 페이지의 목적, 유지보수 방법을 설명합니다.

## 📚 현재 Wiki 구조

### 1. 핵심 페이지

#### [[Home]]
- **목적**: 프로젝트 첫 페이지, 전체 개요 및 빠른 시작 가이드
- **내용**:
  - 프로젝트 소개 및 주요 기능
  - 빠른 시작 가이드 (요구사항, 배포, 사용법)
  - 문서 구조 네비게이션
  - 다른 위키 페이지로의 링크
- **업데이트 빈도**: 낮음 (주요 기능 추가 시)
- **유지보수**: 수동
- **상태**: ✅ 업데이트 완료 (2026-01-30)

#### [[Architecture]]
- **목적**: 시스템 아키텍처 및 기술 스택 상세 설명
- **내용**:
  - 시스템 개요 및 다이어그램 (Mermaid)
  - 주요 컴포넌트 설명 (Webhook, Worker, API Clients)
  - 데이터 플로우 (Issue Hook, Note Hook, Wiki 통합)
  - 기술 스택 및 배포 아키텍처
  - 핵심 설계 원칙 (WebFlux, 무한루프 방지, 브랜치 관리)
- **업데이트 빈도**: 중간 (아키텍처 변경 시)
- **유지보수**: 수동 또는 @fluffybot 요청
- **상태**: ✅ 존재 (정기 검토 필요)

#### [[Development-Guide]]
- **목적**: 개발 환경 설정 및 로컬 개발 가이드
- **내용**:
  - 개발 환경 요구사항 (Java, Gradle, Docker 등)
  - 로컬 개발 환경 설정 (환경변수, 빌드, 실행)
  - 코드 구조 및 주요 컴포넌트 설명
  - WebFlux 리액티브 프로그래밍 가이드
  - Git 컨벤션 (브랜치명, 커밋 메시지)
  - 테스트 및 디버깅 방법
  - Worker Job 로컬 테스트
  - CI/CD 파이프라인 설명
- **업데이트 빈도**: 중간 (개발 프로세스 변경 시)
- **유지보수**: 수동
- **상태**: ✅ 생성 완료 (2026-01-30)

#### [[Deployment]]
- **목적**: 배포 방법 및 운영 가이드
- **내용**:
  - 배포 요구사항 (인프라, API 키, 리소스)
  - Helm 차트로 배포 (기본/커스텀 설치)
  - 설정 커스터마이징 (values.yaml 상세)
  - 환경별 설정 예시 (dev, prod)
  - GitLab 웹훅 설정
  - 운영 및 모니터링 (로그, 리소스, 헬스체크)
  - 업그레이드 및 롤백 절차
  - 문제 해결 (일반적인 배포 문제)
- **업데이트 빈도**: 중간 (배포 프로세스 변경 시)
- **유지보수**: 수동
- **상태**: ✅ 생성 완료 (2026-01-30)

#### [[API-Reference]]
- **목적**: API 엔드포인트 및 페이로드 레퍼런스
- **내용**:
  - Webhook API (POST /webhook/gitlab)
  - Job 관리 API (GET /jobs, /jobs/{name}, /jobs/{name}/logs)
  - Health Check API (GET /actuator/health)
  - GitLab Webhook 페이로드 구조 (Issue Hook, Note Hook, MR Hook)
  - 응답 형식 및 HTTP 상태 코드
  - 요청/응답 예시 (curl)
- **업데이트 빈도**: 중간 (API 변경 시)
- **유지보수**: 수동
- **상태**: ✅ 생성 완료 (2026-01-30)

#### [[Troubleshooting]]
- **목적**: 문제 해결 가이드 및 FAQ
- **내용**:
  - 일반적인 문제 (봇이 응답하지 않음, MR 생성 실패)
  - Webhook 관련 문제 (수신 안됨, 무시됨)
  - Worker Job 관련 문제 (생성 안됨, 실패, 타임아웃)
  - 무한루프 문제
  - GitLab API 문제 (인증 실패, Wiki API)
  - Anthropic API 문제
  - 디버깅 팁 (로그 수집, 상세 로깅)
  - FAQ (10개 항목)
- **업데이트 빈도**: 중간 (이슈 해결 시 추가)
- **유지보수**: 수동 (이슈 해결 경험 누적)
- **상태**: ✅ 생성 완료 (2026-01-30)

### 2. 참고 페이지

#### [[Recent-Changes]]
- **목적**: 최근 변경사항 자동 기록
- **내용**:
  - MR 머지 시 자동 추가되는 변경 이력
  - 이슈 번호, MR 번호, 브랜치, 커밋 메시지
  - 월별 구분
- **업데이트 빈도**: 높음 (MR 머지마다)
- **유지보수**: 자동 (wiki-update.sh)
- **상태**: ✅ 존재 (자동 업데이트 중)

#### [[Wiki-Management]]
- **목적**: 위키 관리 및 활용 방법
- **내용**:
  - 위키 구조 설명
  - 위키 초기화 방법
  - CLAUDE.md vs Wiki 구분
  - 토큰 효율성 고려사항
  - 위키 페이지 작성 가이드
  - 위키 백업 방법
- **업데이트 빈도**: 낮음
- **유지보수**: 수동
- **상태**: ✅ 존재

## 🔄 Wiki 업데이트 워크플로우

### 자동 업데이트 (Recent-Changes)

```
MR 머지
    ↓
MergeRequestEventHandler 감지
    ↓
WorkerService가 wiki 모드로 Job 생성
    ↓
wiki-update.sh 실행
    ↓
Recent-Changes 페이지 업데이트
```

**처리 파일**:
- `src/main/java/com/esc/fluffybot/webhook/handler/MergeRequestEventHandler.java`
- `worker/scripts/wiki-update.sh`

### 수동 업데이트

1. **GitLab UI에서 직접 편집**:
   - 프로젝트 → Wiki → 페이지 선택 → Edit

2. **Git 클론 후 편집**:
   ```bash
   git clone https://gitlab.esc-bot.com/esc/fluffybot.wiki.git
   cd fluffybot.wiki
   # 파일 편집
   git commit -am "docs: 위키 페이지 업데이트"
   git push
   ```

3. **@fluffybot에게 요청**:
   ```
   @fluffybot Architecture 위키 페이지를 업데이트해줘.
   최근 추가된 MergeRequestEventHandler와 wiki-update.sh를 포함해서.
   ```

## 📋 Wiki 페이지 작성 가이드

### 마크다운 형식
- GitLab Flavored Markdown 사용
- 코드 블록에 언어 지정: ```java, ```bash
- Mermaid 다이어그램 지원

### 구조화
- 명확한 제목 계층 (# ## ###)
- 목차는 GitLab이 자동 생성
- 관련 페이지 링크: `[[Page-Name]]`

### 코드 예제
- 실행 가능한 코드 제공
- 주석으로 설명 추가
- 환경 변수, 파일 경로 구체적으로 명시

## 🎯 CLAUDE.md vs Wiki 구분

### CLAUDE.md 사용
- **목적**: Claude Code가 작업 시 참고할 핵심 가이드
- **특징**: 짧고 간결 (토큰 효율성)
- **내용**:
  - 프로젝트 개요
  - 주요 디렉토리 구조
  - 핵심 규칙 (WebFlux, 무한루프 방지, 브랜치 관리)
  - Git 컨벤션
  - 빠른 명령어
  - Wiki 링크

### Wiki 사용
- **목적**: 상세한 문서 및 아키텍처 설명
- **특징**: 장문의 구조화된 문서
- **내용**:
  - 상세 아키텍처 다이어그램
  - 개발 가이드 및 튜토리얼
  - API 레퍼런스
  - 배포 가이드
  - 문제 해결 가이드

## 📊 현재 상태

### ✅ 완료된 페이지
- [x] Home (2026-01-30 업데이트)
- [x] Architecture (기존, 정기 검토 필요)
- [x] Development-Guide (2026-01-30 생성)
- [x] Deployment (2026-01-30 생성)
- [x] API-Reference (2026-01-30 생성)
- [x] Troubleshooting (2026-01-30 생성)
- [x] Recent-Changes (자동 업데이트 중)
- [x] Wiki-Management (기존)

### 📝 향후 추가 가능한 페이지
- [ ] Security-Guide (보안 설정 및 모범 사례)
- [ ] Performance-Tuning (성능 최적화 가이드)
- [ ] Migration-Guide (버전 업그레이드 마이그레이션)
- [ ] Use-Cases (실제 사용 사례 및 예제)

### 🔧 유지보수 지침

1. **분기별 검토 필요**:
   - Architecture 페이지: 코드 변경 시 다이어그램 업데이트
   - Development-Guide 페이지: 개발 프로세스 변경 시 반영
   - Deployment 페이지: Helm 차트 변경 시 업데이트

2. **자동 업데이트 모니터링**:
   - Recent-Changes 페이지: wiki-update.sh 정상 동작 확인
   - 오래된 항목 아카이브 (연 1회)

3. **FAQ 확장**:
   - Troubleshooting 페이지: 새로운 이슈 해결 시 FAQ 추가
   - 실제 사용자 질문을 기반으로 확장

## 🛠️ 위키 초기화 스크립트

프로젝트에 처음으로 위키를 설정:

```bash
export GITLAB_URL=https://gitlab.esc-bot.com
export GITLAB_TOKEN=glpat-xxx
export PROJECT_ID=2

# 기본 위키 페이지 생성
./scripts/init-wiki.sh
```

## 📚 참고 자료

- [GitLab Wiki Documentation](https://docs.gitlab.com/ee/user/project/wiki/)
- [GitLab Wiki API](https://docs.gitlab.com/ee/api/wikis.html)
- [GitLab Flavored Markdown](https://docs.gitlab.com/ee/user/markdown.html)
- [Mermaid Diagrams](https://mermaid.js.org/)

## 🔐 위키 백업

```bash
# Wiki를 Git 저장소로 클론하여 백업
git clone https://gitlab.esc-bot.com/esc/fluffybot.wiki.git fluffybot-wiki-backup
cd fluffybot-wiki-backup
git log  # 히스토리 확인
```

---

**Last Updated**: 2026-01-30
**Maintainer**: Fluffybot Team
