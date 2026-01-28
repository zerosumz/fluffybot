package com.esc.fluffybot.webhook.handler;

import com.esc.fluffybot.anthropic.client.AnthropicApiClient;
import com.esc.fluffybot.config.GitLabProperties;
import com.esc.fluffybot.gitlab.client.GitLabApiClient;
import com.esc.fluffybot.webhook.dto.MergeRequestNotePayload;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.stereotype.Service;
import reactor.core.publisher.Mono;
import reactor.core.scheduler.Schedulers;

/**
 * Merge Request 라인 코멘트 핸들러
 * 다른 사용자의 라인 코멘트에 AI가 응답
 */
@Slf4j
@Service
@RequiredArgsConstructor
public class MergeRequestNoteHandler {

    private final AnthropicApiClient anthropicClient;
    private final GitLabApiClient gitLabClient;
    private final GitLabProperties gitLabProperties;

    public Mono<Void> handleLineComment(MergeRequestNotePayload payload) {
        String comment = payload.getObjectAttributes().getNote();
        Long projectId = payload.getProject().getId();
        Long mrIid = payload.getMergeRequest().getIid();
        String username = payload.getUser().getUsername();

        // Ignore comments from fluffybot itself
        if (gitLabProperties.getBotUsername().equals(username)) {
            log.debug("Ignoring comment from fluffybot");
            return Mono.empty();
        }

        // Check if comment mentions @fluffybot
        if (!comment.contains("@" + gitLabProperties.getBotUsername())) {
            log.debug("Comment does not mention fluffybot, ignoring");
            return Mono.empty();
        }

        // 라인 코멘트가 아니면 무시
        if (!payload.isLineComment()) {
            log.debug("Not a line comment, ignoring");
            return Mono.empty();
        }

        log.info("Processing line comment on project={}, MR={}", projectId, mrIid);

        // 라인 정보 추출
        var position = payload.getObjectAttributes().getPosition();
        String filePath = position.getNewPath() != null ? position.getNewPath() : position.getOldPath();
        Integer lineNumber = position.getNewLine() != null ? position.getNewLine() : position.getOldLine();

        return gitLabClient.getMergeRequest(projectId, mrIid)
            .flatMap(mrData -> {
                String mrTitle = (String) mrData.get("title");
                String mrDescription = (String) mrData.getOrDefault("description", "");

                // 코드 변경사항 가져오기
                return gitLabClient.getMergeRequestChanges(projectId, mrIid)
                    .flatMap(changes -> {
                        String codeContext = extractCodeContext(changes, filePath, lineNumber);

                        String prompt = buildLineCommentPrompt(
                            comment,
                            mrTitle,
                            mrDescription,
                            filePath,
                            lineNumber,
                            codeContext
                        );

                        return anthropicClient.chat(prompt)
                            .flatMap(response ->
                                gitLabClient.postMergeRequestComment(projectId, mrIid, response)
                            );
                    });
            })
            .subscribeOn(Schedulers.boundedElastic())
            .doOnError(error -> log.error("Failed to handle line comment: {}", error.getMessage()))
            .onErrorResume(error ->
                gitLabClient.postMergeRequestComment(projectId, mrIid,
                    "❌ 라인 코멘트 처리 중 오류가 발생했습니다: " + error.getMessage())
            )
            .then();
    }

    private String buildLineCommentPrompt(
        String comment,
        String mrTitle,
        String mrDescription,
        String filePath,
        Integer lineNumber,
        String codeContext
    ) {
        return String.format("""
            당신은 GitLab Merge Request의 코드 리뷰 AI 어시스턴트 fluffybot입니다.
            라인 코멘트에 대해 상세하고 유용한 설명을 제공합니다.

            응답 시 다음 규칙을 따르세요:
            - 한글로 응답
            - 간결하고 명확하게 설명
            - 필요시 mermaid 다이어그램 사용 (```mermaid ... ```)
            - 코드 예시를 포함할 수 있음

            # MR 정보
            - 제목: %s
            - 설명: %s

            # 코멘트 위치
            - 파일: %s
            - 라인: %d

            # 코드 컨텍스트
            ```
            %s
            ```

            # 사용자 질문
            %s

            ---
            위 정보를 바탕으로 사용자의 질문에 답변하세요.
            """,
            mrTitle,
            mrDescription,
            filePath,
            lineNumber,
            codeContext,
            comment
        );
    }

    private String extractCodeContext(Object changes, String filePath, Integer lineNumber) {
        // TODO: 실제 diff에서 해당 라인 주변 코드 추출
        // 지금은 간단히 파일명과 라인 정보만 반환
        return String.format("File: %s, Line: %d", filePath, lineNumber);
    }
}
