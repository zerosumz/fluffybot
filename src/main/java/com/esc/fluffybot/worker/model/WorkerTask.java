package com.esc.fluffybot.worker.model;

import lombok.Builder;
import lombok.Data;

@Data
@Builder
public class WorkerTask {
    private String gitlabUrl;
    private String gitlabToken;
    private String botUsername;
    private String projectPath;
    private Long projectId;
    private Long issueIid;
    private String anthropicApiKey;
}
