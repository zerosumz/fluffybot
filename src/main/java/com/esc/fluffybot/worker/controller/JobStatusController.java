package com.esc.fluffybot.worker.controller;

import com.esc.fluffybot.worker.dto.JobStatusResponse;
import com.esc.fluffybot.worker.service.JobStatusService;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;
import reactor.core.publisher.Flux;
import reactor.core.publisher.Mono;

@Slf4j
@RestController
@RequestMapping("/jobs")
@RequiredArgsConstructor
public class JobStatusController {

    private final JobStatusService jobStatusService;

    @GetMapping
    public Flux<JobStatusResponse> listJobs() {
        log.debug("Listing all jobs");
        return jobStatusService.listJobs();
    }

    @GetMapping("/{name}")
    public Mono<ResponseEntity<JobStatusResponse>> getJobStatus(@PathVariable String name) {
        log.debug("Getting job status: {}", name);
        return jobStatusService.getJobStatus(name)
            .map(ResponseEntity::ok)
            .defaultIfEmpty(ResponseEntity.notFound().build());
    }

    @GetMapping("/{name}/logs")
    public Mono<ResponseEntity<String>> getJobLogs(@PathVariable String name) {
        log.debug("Getting job logs: {}", name);
        return jobStatusService.getJobLogs(name)
            .map(logs -> ResponseEntity.ok()
                .header("Content-Type", "text/plain; charset=utf-8")
                .body(logs))
            .onErrorResume(e -> {
                log.error("Failed to get job logs: {}", e.getMessage());
                return Mono.just(ResponseEntity.internalServerError()
                    .body("Failed to get job logs: " + e.getMessage()));
            });
    }
}
