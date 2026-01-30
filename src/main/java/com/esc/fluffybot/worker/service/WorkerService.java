package com.esc.fluffybot.worker.service;

import com.esc.fluffybot.config.GitLabProperties;
import com.esc.fluffybot.config.WorkerProperties;
import com.esc.fluffybot.gitlab.client.GitLabApiClient;
import com.esc.fluffybot.webhook.dto.GitLabWebhookPayload;
import com.esc.fluffybot.worker.exception.PodCreationException;
import com.esc.fluffybot.worker.model.WorkerTask;
import io.fabric8.kubernetes.api.model.*;
import io.fabric8.kubernetes.api.model.batch.v1.Job;
import io.fabric8.kubernetes.api.model.batch.v1.JobBuilder;
import io.fabric8.kubernetes.client.KubernetesClient;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.stereotype.Service;
import reactor.core.publisher.Mono;

import java.time.Instant;
import java.util.Map;

@Slf4j
@Service
@RequiredArgsConstructor
public class WorkerService {

    private final KubernetesClient kubernetesClient;
    private final WorkerProperties workerProperties;
    private final GitLabProperties gitLabProperties;
    private final GitLabApiClient gitLabApiClient;

    public Mono<String> createWorkerPod(GitLabWebhookPayload payload, String taskDescription) {
        WorkerTask task = buildWorkerTask(payload, taskDescription);
        String jobName = generateJobName(task.getIssueIid());

        return Mono.fromCallable(() -> {
            try {
                Job job = buildJobSpec(jobName, task);

                Job createdJob = kubernetesClient.batch().v1().jobs()
                    .inNamespace(workerProperties.getNamespace())
                    .resource(job)
                    .create();

                log.info("Created worker job: {} in namespace: {}",
                    createdJob.getMetadata().getName(),
                    workerProperties.getNamespace());

                return createdJob.getMetadata().getName();

            } catch (Exception e) {
                log.error("Failed to create worker job: {}", e.getMessage(), e);

                postErrorComment(task, e.getMessage());

                throw new PodCreationException("Failed to create worker job: " + e.getMessage(), e);
            }
        });
    }

    private String generateJobName(Long issueIid) {
        long timestamp = Instant.now().getEpochSecond();
        return String.format("fluffybot-worker-%d-%d", issueIid, timestamp);
    }

    private WorkerTask buildWorkerTask(GitLabWebhookPayload payload, String taskDescription) {
        return WorkerTask.builder()
            .gitlabUrl(gitLabProperties.getUrl())
            .gitlabToken(gitLabProperties.getToken())
            .botUsername(gitLabProperties.getBotUsername())
            .projectPath(payload.getProject().getPathWithNamespace())
            .projectId(payload.getProject().getId())
            .issueIid(payload.getIssueIid())
            .anthropicApiKey(workerProperties.getAnthropicApiKey())
            .skipMrCreation(false)
            .build();
    }

    private Job buildJobSpec(String jobName, WorkerTask task) {
        return new JobBuilder()
            .withNewMetadata()
                .withName(jobName)
                .withNamespace(workerProperties.getNamespace())
                .withLabels(Map.of(
                    "app", "fluffybot-worker",
                    "managed-by", "fluffybot-webhook",
                    "project-id", String.valueOf(task.getProjectId()),
                    "issue-iid", String.valueOf(task.getIssueIid())
                ))
            .endMetadata()
            .withNewSpec()
                .withTtlSecondsAfterFinished(3600)
                .withBackoffLimit(0)
                .withNewTemplate()
                    .withNewMetadata()
                        .withLabels(Map.of(
                            "app", "fluffybot-worker",
                            "managed-by", "fluffybot-webhook",
                            "project-id", String.valueOf(task.getProjectId()),
                            "issue-iid", String.valueOf(task.getIssueIid())
                        ))
                    .endMetadata()
                    .withNewSpec()
                        .withImagePullSecrets(new LocalObjectReferenceBuilder()
                          .withName("fluffy-registry-secret")
                          .build())
                        .withRestartPolicy("Never")
                        .addNewContainer()
                            .withName("worker")
                            .withImage(workerProperties.getImage())
                            .withCommand("/entrypoint.sh")
                            .withEnv(
                                new EnvVar("GITLAB_URL", task.getGitlabUrl(), null),
                                new EnvVar("GITLAB_TOKEN", task.getGitlabToken(), null),
                                new EnvVar("BOT_USERNAME", task.getBotUsername(), null),
                                new EnvVar("PROJECT_PATH", task.getProjectPath(), null),
                                new EnvVar("PROJECT_ID", String.valueOf(task.getProjectId()), null),
                                new EnvVar("ISSUE_IID", String.valueOf(task.getIssueIid()), null),
                                new EnvVar("ANTHROPIC_API_KEY", task.getAnthropicApiKey(), null),
                                new EnvVar("SKIP_MR_CREATION", String.valueOf(task.isSkipMrCreation()), null)
                            )
                            .withNewResources()
                                .withRequests(Map.of(
                                    "cpu", new Quantity(workerProperties.getCpuRequest()),
                                    "memory", new Quantity(workerProperties.getMemoryRequest())
                                ))
                                .withLimits(Map.of(
                                    "cpu", new Quantity(workerProperties.getCpuLimit()),
                                    "memory", new Quantity(workerProperties.getMemoryLimit())
                                ))
                            .endResources()
                            .addNewVolumeMount()
                                .withName("workspace")
                                .withMountPath("/workspace")
                            .endVolumeMount()
                        .endContainer()
                        .addNewVolume()
                            .withName("workspace")
                            .withNewEmptyDir()
                            .endEmptyDir()
                        .endVolume()
                    .endSpec()
                .endTemplate()
            .endSpec()
            .build();
    }

    private void postErrorComment(WorkerTask task, String errorMessage) {
        String comment = String.format(
            "❌ Worker Pod 생성 실패\n\n오류: %s\n\n관리자에게 문의해주세요.",
            errorMessage
        );

        gitLabApiClient.postComment(task.getProjectId(), task.getIssueIid(), comment)
            .doOnError(e -> log.error("Failed to post error comment: {}", e.getMessage()))
            .subscribe();
    }
}
