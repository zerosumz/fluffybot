# Fluffybot Scripts

이 디렉토리는 Fluffybot 프로젝트 관리를 위한 유틸리티 스크립트를 포함합니다.

## 위키 관리

Fluffybot은 프로젝트 위키를 자동으로 관리합니다.

### 위키 활용

- **Worker Job**: 작업 시작 시 모든 위키 페이지를 읽어 Claude에게 전달
- **Note Hook**: `@fluffybot` 멘션 시 위키 컨텍스트를 참고하여 답변
- **자동 업데이트**: 작업 완료 시 Recent-Changes 위키 페이지 또는 CLAUDE.md를 자동으로 업데이트

### 위키 수동 관리

1. **GitLab 웹 UI에서 직접 수정**
   - 프로젝트 > Wiki > 해당 페이지 > Edit

2. **Git을 통한 업데이트**
   ```bash
   git clone https://your-gitlab.com/your-org/your-project.wiki.git
   cd your-project.wiki
   # 파일 수정
   git commit -am "docs: 위키 페이지 업데이트"
   git push
   ```

### Wiki vs CLAUDE.md

- **CLAUDE.md**: 필수 파일, Fluffybot 동작 방식 및 최근 변경사항 (위키가 없으면 여기에 모두 기록)
- **Wiki**: 선택 사항 (권장), 프로젝트 상세 정보, 아키텍처 문서 등
