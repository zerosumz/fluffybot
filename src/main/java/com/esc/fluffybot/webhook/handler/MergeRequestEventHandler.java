package com.esc.fluffybot.webhook.handler;

import com.esc.fluffybot.gitlab.client.GitLabApiClient;
import com.esc.fluffybot.webhook.dto.GitLabWebhookPayload;
import com.esc.fluffybot.webhook.dto.MergeRequestHookPayload;
import com.esc.fluffybot.webhook.dto.ObjectAttributes;
import com.esc.fluffybot.worker.service.WorkerService;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.stereotype.Component;
import reactor.core.publisher.Mono;

/**
 * MR 머지 이벤트를 처리하여 Wiki 업데이트 Worker를 생성하는 핸들러
 */
@Slf4j
@Component
@RequiredArgsConstructor
public class MergeRequestEventHandler {

    private final WorkerService workerService;
    private final GitLabApiClient gitLabApiClient;

    /**
     * MR 머지 완료 시 Wiki 업데이트를 위한 Worker Job 생성
     */
    public Mono<Void> handleMergeEvent(MergeRequestHookPayload payload) {
        Long projectId = payload.getProjectId();
        Long mrIid = payload.getMrIid();
        String description = payload.getObjectAttributes().getDescription();

        log.info("Processing MR merge event: project={}, MR={}", projectId, mrIid);

        // MR description에서 관련 이슈 번호 추출 (Closes #N 형식)
        Long issueIid = extractIssueIidFromDescription(description);

        if (issueIid == null) {
            log.warn("No issue IID found in MR description, skipping wiki update");
            return Mono.empty();
        }

        // GitLabWebhookPayload 형식으로 변환하여 Worker 생성
        // (WorkerService가 GitLabWebhookPayload를 받도록 설계되어 있음)
        return gitLabApiClient.getIssue(projectId, issueIid)
            .flatMap(issue -> {
                GitLabWebhookPayload webhookPayload = createWebhookPayloadFromIssue(payload, issue, issueIid);
                String taskDescription = String.format("Wiki update after MR !%d merge", mrIid);

                return workerService.createWorkerPod(webhookPayload, taskDescription, "wiki", mrIid)
                    .doOnSuccess(jobName -> log.info("Created wiki update worker: {}", jobName))
                    .then();
            })
            .onErrorResume(error -> {
                log.error("Failed to create wiki update worker: {}", error.getMessage(), error);
                // Wiki 업데이트 실패는 전체 프로세스에 영향을 주지 않도록 에러를 무시
                return Mono.empty();
            });
    }

    /**
     * MR description에서 Closes #N 형식으로 이슈 번호 추출
     */
    private Long extractIssueIidFromDescription(String description) {
        if (description == null || description.isEmpty()) {
            return null;
        }

        // "Closes #123", "closes #123", "Fixes #123" 등의 패턴 찾기
        String[] patterns = {"Closes #", "closes #", "Fixes #", "fixes #", "Resolves #", "resolves #"};

        for (String pattern : patterns) {
            int index = description.indexOf(pattern);
            if (index >= 0) {
                int start = index + pattern.length();
                StringBuilder numberStr = new StringBuilder();
                for (int i = start; i < description.length() && Character.isDigit(description.charAt(i)); i++) {
                    numberStr.append(description.charAt(i));
                }
                if (numberStr.length() > 0) {
                    try {
                        return Long.parseLong(numberStr.toString());
                    } catch (NumberFormatException e) {
                        log.warn("Failed to parse issue IID: {}", numberStr);
                    }
                }
            }
        }

        return null;
    }

    /**
     * Issue 정보와 MR 정보를 결합하여 GitLabWebhookPayload 생성
     */
    private GitLabWebhookPayload createWebhookPayloadFromIssue(
            MergeRequestHookPayload mrPayload,
            Object issueData,
            Long issueIid) {

        GitLabWebhookPayload webhookPayload = new GitLabWebhookPayload();
        webhookPayload.setObjectKind("issue");
        webhookPayload.setProject(mrPayload.getProject());
        webhookPayload.setUser(mrPayload.getUser());

        // ObjectAttributes 설정 (이슈 정보)
        ObjectAttributes objectAttributes = new ObjectAttributes();
        objectAttributes.setIid(issueIid);
        objectAttributes.setAction("update");
        objectAttributes.setTitle("Wiki Update");
        objectAttributes.setDescription("Updating wiki after MR merge");
        webhookPayload.setObjectAttributes(objectAttributes);

        return webhookPayload;
    }
}
