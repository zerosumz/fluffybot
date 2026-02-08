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
    private boolean skipMrCreation;
    @Builder.Default
    private String taskMode = "issue";  // "issue" or "wiki"
    private Long mrIid;  // Used only for wiki mode
    private String descriptionPrevious;  // Previous issue description (for incremental work)
    private String descriptionCurrent;   // Current issue description (for incremental work)
}
