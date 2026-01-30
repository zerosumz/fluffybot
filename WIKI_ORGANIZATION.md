# Fluffybot Wiki 구조 및 관리 가이드

이 문서는 Fluffybot 프로젝트의 GitLab Wiki 구조와 각 페이지의 목적, 유지보수 방법을 설명합니다.

## 📚 현재 Wiki 구조

### 1. 핵심 페이지 (현재 존재)

#### [[Home]]
- **목적**: 프로젝트 첫 페이지, 전체 개요 및 빠른 시작 가이드
- **내용**:
  - 프로젝트 소개 및 주요 기능
  - 빠른 시작 가이드
  - 다른 위키 페이지로의 네비게이션
- **업데이트 빈도**: 낮음 (주요 기능 추가 시)
- **유지보수**: 수동

#### [[Architecture]]
- **목적**: 시스템 아키텍처 및 기술 스택 상세 설명
- **내용**:
  - 시스템 개요 및 다이어그램
  - 주요 컴포넌트 설명
  - 데이터 플로우 (Issue Hook, Note Hook, Wiki 통합)
  - 기술 스택 및 배포 아키텍처
  - 핵심 설계 원칙 (WebFlux, 무한루프 방지 등)
- **업데이트 빈도**: 중간 (아키텍처 변경 시)
- **유지보수**: 수동 또는 @fluffybot 요청

#### [[Recent-Changes]]
- **목적**: 최근 변경사항 자동 기록
- **내용**:
  - MR 머지 시 자동 추가되는 변경 이력
  - 이슈 번호, MR 번호, 브랜치, 커밋 메시지
- **업데이트 빈도**: 높음 (MR 머지마다)
- **유지보수**: 자동 (wiki-update.sh)

#### [[Wiki-Management]]
- **목적**: 위키 관리 및 활용 방법
- **내용**:
  - 위키 구조 설명
  - 위키 초기화 방법
  - CLAUDE.md vs Wiki 구분
  - 토큰 효율성 고려사항
- **업데이트 빈도**: 낮음
- **유지보수**: 수동

### 2. 권장 추가 페이지 (README에서 참조, 생성 필요)

#### [[Development-Guide]] (권장)
- **목적**: 개발 환경 설정 및 로컬 개발 가이드
- **내용 예시**:
  - 로컬 개발 환경 설정
  - 환경변수 설정
  - 로컬에서 Webhook 테스트하는 방법
  - 코드 컨벤션 및 WebFlux 가이드
  - Worker Job 로컬 테스트 방법
- **업데이트 빈도**: 중간
- **유지보수**: 수동

#### [[Deployment]] (권장)
- **목적**: 배포 방법 및 설정
- **내용 예시**:
  - Helm 차트 배포 상세 가이드
  - values.yaml 설정 옵션
  - 환경별 배포 예시 (dev, staging, prod)
  - 업그레이드 및 롤백 절차
  - GitLab 웹훅 설정
- **업데이트 빈도**: 중간
- **유지보수**: 수동

#### [[API-Reference]] (권장)
- **목적**: API 엔드포인트 레퍼런스
- **내용 예시**:
  - Webhook 엔드포인트 상세 설명
  - Job 관리 API
  - 요청/응답 예시
  - GitLab Webhook 페이로드 구조
- **업데이트 빈도**: 중간 (API 변경 시)
- **유지보수**: 수동

#### [[Troubleshooting]] (권장)
- **목적**: 문제 해결 가이드 및 FAQ
- **내용 예시**:
  - 일반적인 문제 및 해결 방법
  - Worker Job 실패 원인 및 디버깅
  - 무한루프 발생 시 대처
  - 로그 확인 방법
  - FAQ
- **업데이트 빈도**: 중간 (이슈 해결 시 추가)
- **유지보수**: 수동 (이슈 해결 경험 누적)

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

## 📊 현재 상태 및 TODO

### ✅ 완료된 페이지
- [x] Home
- [x] Architecture
- [x] Recent-Changes
- [x] Wiki-Management

### 📝 생성 권장 페이지
- [ ] Development-Guide (개발 환경 설정 및 가이드)
- [ ] Deployment (배포 방법 상세)
- [ ] API-Reference (API 엔드포인트 레퍼런스)
- [ ] Troubleshooting (문제 해결 가이드)

### 🔧 개선 권장 사항

1. **Home 페이지 단순화**:
   - 현재 README.md와 중복된 내용이 많음
   - 빠른 시작 가이드만 남기고 상세 내용은 개별 페이지로 분리

2. **Architecture 페이지**:
   - 최신 코드 기준으로 잘 정리됨
   - 정기적인 검토 필요 (분기별)

3. **Recent-Changes 페이지**:
   - 자동 업데이트 잘 동작함
   - 오래된 항목 아카이브 방법 고려 (수동 또는 자동)

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
