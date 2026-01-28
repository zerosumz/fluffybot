# 샘플 프로젝트

이 파일은 AI Teammate(Fluffybot)가 프로젝트를 이해하는 데 사용됩니다.

## 프로젝트 개요

Spring Boot 기반 REST API 서버입니다.

## 기술 스택

- Java 21
- Spring Boot 3.2
- Spring WebFlux
- MyBatis
- PostgreSQL

## 디렉토리 구조

```
src/main/java/com/example/
├── controller/    # REST 컨트롤러
├── service/       # 비즈니스 로직
├── mapper/        # MyBatis 매퍼
├── model/         # 도메인 모델
└── config/        # 설정
```

## 테스트 환경

```bash
# 의존성 실행
docker-compose -f docker-compose.test.yml up -d

# DB 초기화: db/dump.sql 자동 로드됨

# 테스트 실행
./gradlew test

# 로컬 실행
./gradlew bootRun
```

## 빌드

```bash
./gradlew build
```

## Git Convention

- 새 기능: `feature/{issue-id}-{short-desc}`
- 버그 수정: `fix/{issue-id}-{short-desc}`
- 긴급 수정: `hotfix/{issue-id}-{short-desc}`
- 커밋: Conventional Commits
  - feat: 기능 추가
  - fix: 버그 수정
  - refactor: 리팩토링
  - test: 테스트
  - docs: 문서
  - chore: 기타

## 코딩 컨벤션

- 들여쓰기: 4 spaces
- 네이밍: camelCase (변수, 메서드), PascalCase (클래스)
- DTO 필드는 record 사용 권장
- 예외는 GlobalExceptionHandler에서 처리

## 주의사항

- block() 호출 금지 (WebFlux)
- @Transactional은 서비스 레이어에서만
- SQL은 XML 매퍼에 작성 (어노테이션 X)
