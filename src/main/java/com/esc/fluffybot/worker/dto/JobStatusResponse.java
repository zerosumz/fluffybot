package com.esc.fluffybot.worker.dto;

import com.fasterxml.jackson.annotation.JsonFormat;
import lombok.AllArgsConstructor;
import lombok.Builder;
import lombok.NoArgsConstructor;
import lombok.Setter;

import java.time.Instant;
import java.util.Objects;

@Builder
@NoArgsConstructor
@AllArgsConstructor
@Setter
public class JobStatusResponse {
    private String name;
    private String status;
    private Long projectId;
    private Long issueIid;

    @JsonFormat(shape = JsonFormat.Shape.STRING)
    private Instant startTime;

    @JsonFormat(shape = JsonFormat.Shape.STRING)
    private Instant completionTime;

    private Integer succeeded;
    private Integer failed;
    private String message;

    // Custom getters
    public String getName() {
        return name;
    }

    public String getStatus() {
        return status;
    }

    public Long getProjectId() {
        return projectId;
    }

    public Long getIssueIid() {
        return issueIid;
    }

    public Instant getStartTime() {
        return startTime;
    }

    public Instant getCompletionTime() {
        return completionTime;
    }

    // Custom getters to handle null values safely
    public Integer getSucceeded() {
        return Objects.requireNonNullElse(succeeded, 0);
    }

    public Integer getFailed() {
        return Objects.requireNonNullElse(failed, 0);
    }

    public String getMessage() {
        return message;
    }
}
