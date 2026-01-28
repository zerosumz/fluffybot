package com.esc.fluffybot.worker.dto;

import lombok.Builder;
import lombok.Data;

import java.time.Instant;

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
}
