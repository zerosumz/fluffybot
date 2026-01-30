package com.esc.fluffybot.webhook.controller;

import com.esc.fluffybot.config.GitLabProperties;
import com.esc.fluffybot.webhook.dto.GitLabWebhookPayload;
import com.esc.fluffybot.webhook.dto.MergeRequestHookPayload;
import com.esc.fluffybot.webhook.dto.MergeRequestNotePayload;
import com.esc.fluffybot.webhook.dto.NoteHookPayload;
import com.esc.fluffybot.webhook.dto.WebhookResponse;
import com.esc.fluffybot.webhook.handler.MergeRequestEventHandler;
import com.esc.fluffybot.webhook.handler.MergeRequestNoteHandler;
import com.esc.fluffybot.webhook.handler.NoteHookHandler;
import com.esc.fluffybot.webhook.service.WebhookValidationService;
import com.esc.fluffybot.worker.service.WorkerService;
import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;
import reactor.core.publisher.Mono;
import reactor.core.scheduler.Schedulers;

@Slf4j
@RestController
@RequestMapping("/webhook")
@RequiredArgsConstructor
public class GitLabWebhookController {

    private final WebhookValidationService validationService;
    private final WorkerService workerService;
    private final NoteHookHandler noteHookHandler;
    private final MergeRequestNoteHandler mrNoteHandler;
    private final MergeRequestEventHandler mrEventHandler;
    private final GitLabProperties gitLabProperties;
    private final ObjectMapper objectMapper;

    @PostMapping("/gitlab")
    public Mono<ResponseEntity<WebhookResponse>> handleGitLabWebhook(
            @RequestBody JsonNode payload) {

        String objectKind = payload.has("object_kind") ? payload.get("object_kind").asText() : "";

        log.debug("Received webhook: objectKind={}", objectKind);

        // Check if event is from fluffybot itself (prevent infinite loops)
        String username = payload.has("user") && payload.get("user").has("username")
            ? payload.get("user").get("username").asText()
            : "";
        if (gitLabProperties.getBotUsername().equals(username)) {
            log.debug("Ignoring event from fluffybot itself");
            return Mono.just(ResponseEntity.ok(
                WebhookResponse.ignored("Event from bot itself")
            ));
        }

        // Route to appropriate handler based on object_kind
        if ("note".equals(objectKind)) {
            return handleNoteHook(payload);
        } else if ("issue".equals(objectKind)) {
            return handleIssueHook(payload);
        } else if ("merge_request".equals(objectKind)) {
            return handleMergeRequestHook(payload);
        } else {
            log.debug("Unsupported webhook type: {}", objectKind);
            return Mono.just(ResponseEntity.ok(
                WebhookResponse.ignored("Unsupported webhook type")
            ));
        }
    }

    private Mono<ResponseEntity<WebhookResponse>> handleNoteHook(JsonNode payload) {
        try {
            // Check noteable_type to determine if it's an issue or MR comment
            String noteableType = payload.has("object_attributes") &&
                                  payload.get("object_attributes").has("noteable_type")
                ? payload.get("object_attributes").get("noteable_type").asText()
                : "";

            if ("Issue".equals(noteableType)) {
                // Handle issue comment
                NoteHookPayload notePayload = objectMapper.treeToValue(payload, NoteHookPayload.class);

                log.info("Processing issue note hook for project={}, issue={}",
                    notePayload.getProject().getId(),
                    notePayload.getIssue().getIid());

                noteHookHandler.handleComment(notePayload)
                    .subscribeOn(Schedulers.boundedElastic())
                    .doOnError(error -> log.error("Failed to handle comment: {}", error.getMessage()))
                    .subscribe();

                return Mono.just(ResponseEntity.ok(
                    WebhookResponse.accepted("Issue comment processing started")
                ));

            } else if ("MergeRequest".equals(noteableType)) {
                // Handle MR comment (including line comments)
                MergeRequestNotePayload mrPayload = objectMapper.treeToValue(payload, MergeRequestNotePayload.class);

                log.info("Processing MR note hook for project={}, MR={}",
                    mrPayload.getProject().getId(),
                    mrPayload.getMergeRequest().getIid());

                mrNoteHandler.handleLineComment(mrPayload)
                    .subscribeOn(Schedulers.boundedElastic())
                    .doOnError(error -> log.error("Failed to handle MR comment: {}", error.getMessage()))
                    .subscribe();

                return Mono.just(ResponseEntity.ok(
                    WebhookResponse.accepted("MR comment processing started")
                ));

            } else {
                log.debug("Unsupported noteable type: {}", noteableType);
                return Mono.just(ResponseEntity.ok(
                    WebhookResponse.ignored("Unsupported noteable type")
                ));
            }

        } catch (Exception e) {
            log.error("Failed to parse note hook payload: {}", e.getMessage());
            return Mono.just(ResponseEntity.ok(
                WebhookResponse.ignored("Failed to parse payload")
            ));
        }
    }

    private Mono<ResponseEntity<WebhookResponse>> handleIssueHook(JsonNode payload) {
        try {
            GitLabWebhookPayload issuePayload = objectMapper.treeToValue(payload, GitLabWebhookPayload.class);

            log.debug("Issue action={}",
                issuePayload.getObjectAttributes() != null ? issuePayload.getObjectAttributes().getAction() : "null");

            String validationError = validationService.validate(issuePayload);
            if (validationError != null) {
                log.debug("Webhook ignored: {}", validationError);
                return Mono.just(ResponseEntity.ok(
                    WebhookResponse.ignored(validationError)
                ));
            }

            if (!issuePayload.hasAssignee(gitLabProperties.getBotUsername())) {
                log.debug("Bot not assigned, ignoring webhook");
                return Mono.just(ResponseEntity.ok(
                    WebhookResponse.ignored("Bot not assigned")
                ));
            }

            String taskDescription = issuePayload.getTaskDescription();
            Long projectId = issuePayload.getProject().getId();
            Long issueIid = issuePayload.getIssueIid();

            log.info("Processing task for project={}, issue={}", projectId, issueIid);

            workerService.createWorkerPod(issuePayload, taskDescription)
                .subscribeOn(Schedulers.boundedElastic())
                .doOnSuccess(podName -> log.info("Worker pod created: {}", podName))
                .doOnError(error -> log.error("Failed to create worker pod: {}", error.getMessage()))
                .subscribe();

            return Mono.just(ResponseEntity.ok(
                WebhookResponse.accepted("Task accepted and worker pod is being created")
            ));

        } catch (Exception e) {
            log.error("Failed to parse issue hook payload: {}", e.getMessage());
            return Mono.just(ResponseEntity.ok(
                WebhookResponse.ignored("Failed to parse payload")
            ));
        }
    }

    private Mono<ResponseEntity<WebhookResponse>> handleMergeRequestHook(JsonNode payload) {
        try {
            MergeRequestHookPayload mrPayload = objectMapper.treeToValue(payload, MergeRequestHookPayload.class);

            log.debug("MR state={}, action={}",
                mrPayload.getObjectAttributes() != null ? mrPayload.getObjectAttributes().getState() : "null",
                mrPayload.getObjectAttributes() != null ? mrPayload.getObjectAttributes().getAction() : "null");

            // Only handle merge events
            if (!mrPayload.isMerged()) {
                log.debug("MR not merged, ignoring webhook");
                return Mono.just(ResponseEntity.ok(
                    WebhookResponse.ignored("MR not merged")
                ));
            }

            Long projectId = mrPayload.getProjectId();
            Long mrIid = mrPayload.getMrIid();

            log.info("Processing MR merge event for project={}, MR={}", projectId, mrIid);

            mrEventHandler.handleMergeEvent(mrPayload)
                .subscribeOn(Schedulers.boundedElastic())
                .doOnSuccess(v -> log.info("MR merge event processed successfully"))
                .doOnError(error -> log.error("Failed to handle MR merge event: {}", error.getMessage()))
                .subscribe();

            return Mono.just(ResponseEntity.ok(
                WebhookResponse.accepted("MR merge event processing started")
            ));

        } catch (Exception e) {
            log.error("Failed to parse MR hook payload: {}", e.getMessage());
            return Mono.just(ResponseEntity.ok(
                WebhookResponse.ignored("Failed to parse payload")
            ));
        }
    }

    @GetMapping("/health")
    public Mono<String> health() {
        return Mono.just("OK");
    }
}
