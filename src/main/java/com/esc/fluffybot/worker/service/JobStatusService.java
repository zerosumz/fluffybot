package com.esc.fluffybot.worker.service;

import com.esc.fluffybot.config.WorkerProperties;
import com.esc.fluffybot.worker.dto.JobStatusResponse;
import io.fabric8.kubernetes.api.model.Pod;
import io.fabric8.kubernetes.api.model.PodList;
import io.fabric8.kubernetes.api.model.batch.v1.Job;
import io.fabric8.kubernetes.api.model.batch.v1.JobList;
import io.fabric8.kubernetes.api.model.batch.v1.JobStatus;
import io.fabric8.kubernetes.client.KubernetesClient;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.stereotype.Service;
import reactor.core.publisher.Flux;
import reactor.core.publisher.Mono;

import java.time.ZoneId;
import java.time.ZonedDateTime;

@Slf4j
@Service
@RequiredArgsConstructor
public class JobStatusService {

    private final KubernetesClient kubernetesClient;
    private final WorkerProperties workerProperties;

    public Flux<JobStatusResponse> listJobs() {
        return Mono.fromCallable(() -> {
            JobList jobList = kubernetesClient.batch().v1().jobs()
                .inNamespace(workerProperties.getNamespace())
                .withLabel("app", "fluffybot-worker")
                .list();

            return jobList.getItems();
        })
        .flatMapMany(Flux::fromIterable)
        .map(this::mapToJobStatusResponse);
    }

    public Mono<JobStatusResponse> getJobStatus(String jobName) {
        return Mono.fromCallable(() -> {
            Job job = kubernetesClient.batch().v1().jobs()
                .inNamespace(workerProperties.getNamespace())
                .withName(jobName)
                .get();

            if (job == null) {
                return null;
            }

            return mapToJobStatusResponse(job);
        });
    }

    public Mono<String> getJobLogs(String jobName) {
        return Mono.fromCallable(() -> {
            PodList podList = kubernetesClient.pods()
                .inNamespace(workerProperties.getNamespace())
                .withLabel("job-name", jobName)
                .list();

            if (podList.getItems().isEmpty()) {
                return "No pods found for job: " + jobName;
            }

            Pod pod = podList.getItems().get(0);
            String podName = pod.getMetadata().getName();

            return kubernetesClient.pods()
                .inNamespace(workerProperties.getNamespace())
                .withName(podName)
                .getLog();
        });
    }

    private JobStatusResponse mapToJobStatusResponse(Job job) {
        JobStatus status = job.getStatus();
        String jobStatus = determineJobStatus(status);

        String projectId = job.getMetadata().getLabels().get("project-id");
        String issueIid = job.getMetadata().getLabels().get("issue-iid");

        return JobStatusResponse.builder()
            .name(job.getMetadata().getName())
            .status(jobStatus)
            .projectId(projectId != null ? Long.parseLong(projectId) : null)
            .issueIid(issueIid != null ? Long.parseLong(issueIid) : null)
            .startTime(status != null && status.getStartTime() != null ?
                ZonedDateTime.parse(status.getStartTime()).toInstant() : null)
            .completionTime(status != null && status.getCompletionTime() != null ?
                ZonedDateTime.parse(status.getCompletionTime()).toInstant() : null)
            .succeeded(status != null ? status.getSucceeded() : 0)
            .failed(status != null ? status.getFailed() : 0)
            .build();
    }

    private String determineJobStatus(JobStatus status) {
        if (status == null) {
            return "pending";
        }

        if (status.getSucceeded() != null && status.getSucceeded() > 0) {
            return "succeeded";
        }

        if (status.getFailed() != null && status.getFailed() > 0) {
            return "failed";
        }

        if (status.getActive() != null && status.getActive() > 0) {
            return "running";
        }

        return "pending";
    }
}
