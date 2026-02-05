package com.esc.fluffybot.worker.dto;

import lombok.Builder;
import lombok.Data;

import java.time.Instant;
import java.util.Objects;

@Data
@Builder
public class JobStatusResponse {
    private String name;
    private String status;
    private Long projectId;
    private Long issueIid;
    private Instant startTime;
    private Instant completionTime;
    private Integer succeeded;
    private Integer failed;
    private String message;

    // Custom getters to handle null values safely
    public Integer getSucceeded() {
        return Objects.requireNonNullElse(succeeded, 0);
    }

    public Integer getFailed() {
        return Objects.requireNonNullElse(failed, 0);
    }
}
