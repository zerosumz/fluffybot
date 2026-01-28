package com.esc.fluffybot.webhook.handler;

import com.esc.fluffybot.anthropic.client.AnthropicApiClient;
import com.esc.fluffybot.config.GitLabProperties;
import com.esc.fluffybot.gitlab.client.GitLabApiClient;
import com.esc.fluffybot.gitlab.client.GitLabWikiClient;
import com.esc.fluffybot.webhook.dto.NoteHookPayload;
import com.esc.fluffybot.worker.service.WorkerService;
import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.stereotype.Service;
import reactor.core.publisher.Mono;
import reactor.core.scheduler.Schedulers;

import java.util.Map;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

@Slf4j
@Service
@RequiredArgsConstructor
public class NoteHookHandler {

    private final AnthropicApiClient anthropicClient;
    private final GitLabApiClient gitLabClient;
    private final GitLabWikiClient wikiClient;
    private final GitLabProperties gitLabProperties;
    private final ObjectMapper objectMapper;

    private static final Pattern BRANCH_PATTERN = Pattern.compile("브랜치:\\s*`([^`]+)`");
    private static final Pattern MR_PATTERN = Pattern.compile("MR:\\s*!([0-9]+)");
    private static final String FLUFFYBOT_SECTION_MARKER = "\n---\n🤖 **Fluffybot 작업 정보**\n";

    public Mono<Void> handleComment(NoteHookPayload payload) {
        String comment = payload.getObjectAttributes().getNote();
        Long projectId = payload.getProject().getId();
        Long issueIid = payload.getIssue().getIid();
        String username = payload.getUser().getUsername();

        // Ignore comments from fluffybot itself to prevent infinite loops
        if (gitLabProperties.getBotUsername().equals(username)) {
            log.debug("Ignoring comment from fluffybot");
            return Mono.empty();
        }

        // Check if comment mentions @fluffybot
        if (!comment.contains("@" + gitLabProperties.getBotUsername())) {
            log.debug("Comment does not mention fluffybot, ignoring");
            return Mono.empty();
        }

        log.info("Processing comment on project={}, issue={}", projectId, issueIid);

        return gitLabClient.getIssue(projectId, issueIid)
            .flatMap(issueData -> {
                String issueTitle = (String) issueData.get("title");
                String issueDescription = (String) issueData.getOrDefault("description", "");

                // Fetch wiki context
                return wikiClient.getWikiContext(projectId)
                    .map(wikiContext -> buildPrompt(comment, issueTitle, issueDescription, wikiContext))
                    .defaultIfEmpty(buildPrompt(comment, issueTitle, issueDescription, ""))
                    .flatMap(prompt -> anthropicClient.chat(prompt)
                        .flatMap(response -> processResponse(response, projectId, issueIid, issueDescription)));
            })
            .subscribeOn(Schedulers.boundedElastic())
            .doOnError(error -> log.error("Failed to handle comment: {}", error.getMessage()))
            .onErrorResume(error ->
                gitLabClient.postComment(projectId, issueIid,
                    "❌ 코멘트 처리 중 오류가 발생했습니다: " + error.getMessage())
            )
            .then();
    }

    private String buildPrompt(String comment, String issueTitle, String issueDescription, String wikiContext) {
        StringBuilder prompt = new StringBuilder();
        prompt.append("당신은 GitLab 이슈의 AI 어시스턴트 fluffybot입니다.\n");
        prompt.append("사용자의 코멘트에 응답합니다.\n\n");

        // Wiki context가 있으면 추가
        if (wikiContext != null && !wikiContext.isEmpty()) {
            prompt.append("# 프로젝트 위키 컨텍스트\n\n");
            prompt.append(wikiContext);
            prompt.append("\n---\n\n");
        }

        prompt.append("""
            응답 형식 (JSON):
            {
              "type": "answer" | "suggest_prompt",
              "content": "사용자에게 보여줄 답변 (Markdown 형식)"
            }

            규칙:
            - 단순 질문 → type: "answer"
            - 코드 변경 요청 → type: "suggest_prompt", 이슈 본문에 추가할 내용 예시 제안
            - 한글로 응답
            - 이슈를 직접 수정하지 않음
            - JSON 형식으로만 응답 (다른 텍스트 포함 금지)
            - **중요: 순수 JSON만 출력하세요. 마크다운 코드블록(```json)으로 감싸지 마세요.**
            - 필요시 mermaid 다이어그램 사용 (```mermaid ... ```)
            - 복잡한 흐름/구조 설명 시 다이어그램 적극 활용
            - 위키 컨텍스트를 참고하여 프로젝트 구조, 엔티티, 최근 변경사항 등을 정확하게 답변

            Mermaid 예시:
            ```mermaid
            graph TD
                A[시작] --> B[처리]
                B --> C[완료]
            ```

            ---

            이슈 제목: %s

            이슈 설명:
            %s

            ---

            사용자 코멘트: %s
            """);

        return String.format(prompt.toString(), issueTitle, issueDescription, comment);
    }

    private Mono<Void> processResponse(String response, Long projectId, Long issueIid, String originalDescription) {
        try {
            // Remove markdown code block if present
            String cleanedResponse = response;
            if (cleanedResponse.trim().startsWith("```")) {
                cleanedResponse = cleanedResponse.replaceAll("^```(json)?\\s*", "")
                                                 .replaceAll("\\s*```$", "")
                                                 .trim();
            }

            // Parse JSON response
            JsonNode jsonResponse = objectMapper.readTree(cleanedResponse);
            String type = jsonResponse.get("type").asText();
            String content = jsonResponse.get("content").asText();

            return switch (type) {
                case "answer" -> gitLabClient.postComment(projectId, issueIid, content);

                case "suggest_prompt" -> gitLabClient.postComment(projectId, issueIid,
                    "💡 " + content);

                default -> {
                    log.error("Unknown response type: {}", type);
                    yield gitLabClient.postComment(projectId, issueIid,
                        "❌ 응답 처리 중 오류가 발생했습니다.");
                }
            };
        } catch (Exception e) {
            log.error("Failed to parse Anthropic response: {}", e.getMessage());
            return gitLabClient.postComment(projectId, issueIid,
                "❌ AI 응답을 파싱하는 중 오류가 발생했습니다.");
        }
    }

    private String appendToIssueDescription(String originalDescription, String newContent) {
        // Remove existing fluffybot section if present
        int markerIndex = originalDescription.indexOf(FLUFFYBOT_SECTION_MARKER);
        String baseDescription = markerIndex >= 0
            ? originalDescription.substring(0, markerIndex)
            : originalDescription;

        // Append new content
        return baseDescription.trim() + "\n\n" + newContent.trim();
    }

    public static String extractBranchFromDescription(String description) {
        Matcher matcher = BRANCH_PATTERN.matcher(description);
        return matcher.find() ? matcher.group(1) : null;
    }

    public static String appendFluffybotInfo(String description, String branchName, Long mrIid) {
        // Remove existing fluffybot section if present
        int markerIndex = description.indexOf(FLUFFYBOT_SECTION_MARKER);
        String baseDescription = markerIndex >= 0
            ? description.substring(0, markerIndex)
            : description;

        String fluffybotInfo = String.format(
            "%s- 브랜치: `%s`\n- MR: !%d",
            FLUFFYBOT_SECTION_MARKER,
            branchName,
            mrIid
        );

        return baseDescription.trim() + fluffybotInfo;
    }
}
