package com.esc.fluffybot.gitlab.dto;

import com.fasterxml.jackson.annotation.JsonProperty;
import lombok.Builder;
import lombok.Data;

@Data
@Builder
public class CreateMergeRequestRequest {
    @JsonProperty("source_branch")
    private String sourceBranch;

    @JsonProperty("target_branch")
    private String targetBranch;

    private String title;
    private String description;

    @JsonProperty("remove_source_branch")
    private Boolean removeSourceBranch;
}
