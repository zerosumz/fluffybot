package com.esc.fluffybot.webhook.dto;

import com.fasterxml.jackson.annotation.JsonIgnoreProperties;
import com.fasterxml.jackson.annotation.JsonProperty;
import lombok.Data;

/**
 * GitLab Merge Request Hook Payload
 * MR 생성, 업데이트, 머지 이벤트를 위한 페이로드
 */
@Data
@JsonIgnoreProperties(ignoreUnknown = true)
public class MergeRequestHookPayload {

    @JsonProperty("object_kind")
    private String objectKind;

    private ProjectInfo project;

    @JsonProperty("object_attributes")
    private MergeRequestAttributes objectAttributes;

    private UserInfo user;

    @Data
    @JsonIgnoreProperties(ignoreUnknown = true)
    public static class MergeRequestAttributes {
        private Long id;
        private Long iid;
        private String title;
        private String description;

        @JsonProperty("source_branch")
        private String sourceBranch;

        @JsonProperty("target_branch")
        private String targetBranch;

        private String state;  // "opened", "closed", "locked", "merged"
        private String action;  // "open", "close", "reopen", "update", "approved", "unapproved", "approval", "unapproval", "merge"

        @JsonProperty("merge_status")
        private String mergeStatus;  // "unchecked", "checking", "can_be_merged", "cannot_be_merged"
    }

    /**
     * MR이 머지되었는지 확인
     */
    public boolean isMerged() {
        return objectAttributes != null &&
               "merged".equals(objectAttributes.getState()) &&
               "merge".equals(objectAttributes.getAction());
    }

    public Long getMrIid() {
        return objectAttributes != null ? objectAttributes.getIid() : null;
    }

    public Long getProjectId() {
        return project != null ? project.getId() : null;
    }
}
