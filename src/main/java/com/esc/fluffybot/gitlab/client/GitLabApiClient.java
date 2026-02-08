package com.esc.fluffybot.gitlab.client;

import com.esc.fluffybot.gitlab.dto.CreateMergeRequestRequest;
import com.esc.fluffybot.gitlab.dto.CreateNoteRequest;
import com.esc.fluffybot.gitlab.exception.GitLabApiException;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.core.ParameterizedTypeReference;
import org.springframework.stereotype.Service;
import org.springframework.web.reactive.function.client.WebClient;
import reactor.core.publisher.Mono;

import java.util.Map;

@Slf4j
@Service
@RequiredArgsConstructor
public class GitLabApiClient {

    private final WebClient gitLabWebClient;

    public Mono<Void> postComment(Long projectId, Long issueIid, String comment) {
        String uri = String.format("/api/v4/projects/%d/issues/%d/notes", projectId, issueIid);

        CreateNoteRequest request = new CreateNoteRequest(comment);

        return gitLabWebClient.post()
            .uri(uri)
            .bodyValue(request)
            .retrieve()
            .onStatus(
                status -> status.is4xxClientError() || status.is5xxServerError(),
                response -> response.bodyToMono(String.class)
                    .flatMap(body -> {
                        log.error("GitLab API error: status={}, body={}", response.statusCode(), body);
                        return Mono.error(new GitLabApiException(
                            "Failed to post comment: " + response.statusCode()
                        ));
                    })
            )
            .bodyToMono(Void.class)
            .doOnSuccess(v -> log.debug("Comment posted to project={}, issue={}", projectId, issueIid))
            .onErrorResume(e -> {
                log.error("Failed to post comment: {}", e.getMessage());
                return Mono.empty();
            });
    }

    public Mono<Long> createMergeRequest(
            Long projectId,
            String sourceBranch,
            String targetBranch,
            String title,
            String description) {

        String uri = String.format("/api/v4/projects/%d/merge_requests", projectId);

        CreateMergeRequestRequest request = CreateMergeRequestRequest.builder()
            .sourceBranch(sourceBranch)
            .targetBranch(targetBranch)
            .title(title)
            .description(description)
            .removeSourceBranch(true)
            .build();

        return gitLabWebClient.post()
            .uri(uri)
            .bodyValue(request)
            .retrieve()
            .onStatus(
                status -> status.is4xxClientError() || status.is5xxServerError(),
                response -> response.bodyToMono(String.class)
                    .flatMap(body -> {
                        log.error("GitLab API error: status={}, body={}", response.statusCode(), body);
                        return Mono.error(new GitLabApiException(
                            "Failed to create merge request: " + response.statusCode()
                        ));
                    })
            )
            .bodyToMono(Map.class)
            .map(response -> {
                Long iid = ((Number) response.get("iid")).longValue();
                log.info("Merge request created: project={}, iid={}", projectId, iid);
                return iid;
            });
    }

    public Mono<Map<String, Object>> getIssue(Long projectId, Long issueIid) {
        String uri = String.format("/api/v4/projects/%d/issues/%d", projectId, issueIid);

        return gitLabWebClient.get()
            .uri(uri)
            .retrieve()
            .onStatus(
                status -> status.is4xxClientError() || status.is5xxServerError(),
                response -> response.bodyToMono(String.class)
                    .flatMap(body -> {
                        log.error("GitLab API error: status={}, body={}", response.statusCode(), body);
                        return Mono.error(new GitLabApiException(
                            "Failed to get issue: " + response.statusCode()
                        ));
                    })
            )
            .bodyToMono(new ParameterizedTypeReference<Map<String, Object>>() {})
            .doOnSuccess(v -> log.debug("Retrieved issue: project={}, iid={}", projectId, issueIid))
            .onErrorResume(e -> {
                log.error("Failed to get issue: {}", e.getMessage());
                return Mono.<Map<String, Object>>error(e);
            });
    }

    public Mono<Void> updateIssueDescription(Long projectId, Long issueIid, String description) {
        String uri = String.format("/api/v4/projects/%d/issues/%d", projectId, issueIid);

        Map<String, String> request = Map.of("description", description);

        return gitLabWebClient.put()
            .uri(uri)
            .bodyValue(request)
            .retrieve()
            .onStatus(
                status -> status.is4xxClientError() || status.is5xxServerError(),
                response -> response.bodyToMono(String.class)
                    .flatMap(body -> {
                        log.error("GitLab API error: status={}, body={}", response.statusCode(), body);
                        return Mono.error(new GitLabApiException(
                            "Failed to update issue description: " + response.statusCode()
                        ));
                    })
            )
            .bodyToMono(Void.class)
            .doOnSuccess(v -> log.debug("Issue description updated: project={}, iid={}", projectId, issueIid))
            .onErrorResume(e -> {
                log.error("Failed to update issue description: {}", e.getMessage());
                return Mono.empty();
            });
    }

    public Mono<Map<String, Object>> getMergeRequest(Long projectId, Long mrIid) {
        String uri = String.format("/api/v4/projects/%d/merge_requests/%d", projectId, mrIid);

        return gitLabWebClient.get()
            .uri(uri)
            .retrieve()
            .onStatus(
                status -> status.is4xxClientError() || status.is5xxServerError(),
                response -> response.bodyToMono(String.class)
                    .flatMap(body -> {
                        log.error("GitLab API error: status={}, body={}", response.statusCode(), body);
                        return Mono.error(new GitLabApiException(
                            "Failed to get merge request: " + response.statusCode()
                        ));
                    })
            )
            .bodyToMono(new ParameterizedTypeReference<Map<String, Object>>() {})
            .doOnSuccess(v -> log.debug("Retrieved merge request: project={}, iid={}", projectId, mrIid))
            .onErrorResume(e -> {
                log.error("Failed to get merge request: {}", e.getMessage());
                return Mono.<Map<String, Object>>error(e);
            });
    }

    public Mono<Object> getMergeRequestChanges(Long projectId, Long mrIid) {
        String uri = String.format("/api/v4/projects/%d/merge_requests/%d/changes", projectId, mrIid);

        return gitLabWebClient.get()
            .uri(uri)
            .retrieve()
            .onStatus(
                status -> status.is4xxClientError() || status.is5xxServerError(),
                response -> response.bodyToMono(String.class)
                    .flatMap(body -> {
                        log.error("GitLab API error: status={}, body={}", response.statusCode(), body);
                        return Mono.error(new GitLabApiException(
                            "Failed to get merge request changes: " + response.statusCode()
                        ));
                    })
            )
            .bodyToMono(Object.class)
            .doOnSuccess(v -> log.debug("Retrieved merge request changes: project={}, iid={}", projectId, mrIid))
            .onErrorResume(e -> {
                log.error("Failed to get merge request changes: {}", e.getMessage());
                return Mono.error(e);
            });
    }

    public Mono<Void> postMergeRequestComment(Long projectId, Long mrIid, String comment) {
        String uri = String.format("/api/v4/projects/%d/merge_requests/%d/notes", projectId, mrIid);

        CreateNoteRequest request = new CreateNoteRequest(comment);

        return gitLabWebClient.post()
            .uri(uri)
            .bodyValue(request)
            .retrieve()
            .onStatus(
                status -> status.is4xxClientError() || status.is5xxServerError(),
                response -> response.bodyToMono(String.class)
                    .flatMap(body -> {
                        log.error("GitLab API error: status={}, body={}", response.statusCode(), body);
                        return Mono.error(new GitLabApiException(
                            "Failed to post MR comment: " + response.statusCode()
                        ));
                    })
            )
            .bodyToMono(Void.class)
            .doOnSuccess(v -> log.debug("Comment posted to project={}, MR={}", projectId, mrIid))
            .onErrorResume(e -> {
                log.error("Failed to post MR comment: {}", e.getMessage());
                return Mono.empty();
            });
    }

    public Mono<java.util.List<Map<String, Object>>> getRelatedMergeRequests(Long projectId, Long issueIid) {
        String uri = String.format("/api/v4/projects/%d/issues/%d/related_merge_requests", projectId, issueIid);

        return gitLabWebClient.get()
            .uri(uri)
            .retrieve()
            .onStatus(
                status -> status.is4xxClientError() || status.is5xxServerError(),
                response -> response.bodyToMono(String.class)
                    .flatMap(body -> {
                        log.error("GitLab API error: status={}, body={}", response.statusCode(), body);
                        return Mono.error(new GitLabApiException(
                            "Failed to get related merge requests: " + response.statusCode()
                        ));
                    })
            )
            .bodyToMono(new ParameterizedTypeReference<java.util.List<Map<String, Object>>>() {})
            .doOnSuccess(v -> log.debug("Retrieved related MRs for issue: project={}, iid={}", projectId, issueIid))
            .onErrorResume(e -> {
                log.error("Failed to get related merge requests: {}", e.getMessage());
                return Mono.just(java.util.List.of());
            });
    }

    public Mono<Map<String, Object>> getMergeRequestDiffs(Long projectId, Long mrIid) {
        String uri = String.format("/api/v4/projects/%d/merge_requests/%d/diffs", projectId, mrIid);

        return gitLabWebClient.get()
            .uri(uri)
            .retrieve()
            .onStatus(
                status -> status.is4xxClientError() || status.is5xxServerError(),
                response -> response.bodyToMono(String.class)
                    .flatMap(body -> {
                        log.error("GitLab API error: status={}, body={}", response.statusCode(), body);
                        return Mono.error(new GitLabApiException(
                            "Failed to get merge request diffs: " + response.statusCode()
                        ));
                    })
            )
            .bodyToMono(new ParameterizedTypeReference<Map<String, Object>>() {})
            .doOnSuccess(v -> log.debug("Retrieved MR diffs: project={}, iid={}", projectId, mrIid))
            .onErrorResume(e -> {
                log.error("Failed to get merge request diffs: {}", e.getMessage());
                return Mono.just(Map.of());
            });
    }
}
