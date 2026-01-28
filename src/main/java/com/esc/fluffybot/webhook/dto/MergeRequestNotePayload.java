package com.esc.fluffybot.webhook.dto;

import com.fasterxml.jackson.annotation.JsonIgnoreProperties;
import com.fasterxml.jackson.annotation.JsonProperty;
import lombok.Data;

/**
 * GitLab Merge Request Note Hook Payload
 * 라인 코멘트에 대한 웹훅 페이로드
 */
@Data
@JsonIgnoreProperties(ignoreUnknown = true)
public class MergeRequestNotePayload {

    @JsonProperty("object_kind")
    private String objectKind;

    private ProjectInfo project;

    @JsonProperty("merge_request")
    private MergeRequestInfo mergeRequest;

    @JsonProperty("object_attributes")
    private MergeRequestNoteAttributes objectAttributes;

    private UserInfo user;

    @Data
    @JsonIgnoreProperties(ignoreUnknown = true)
    public static class MergeRequestInfo {
        private Long id;
        private Long iid;
        private String title;
        private String description;

        @JsonProperty("source_branch")
        private String sourceBranch;

        @JsonProperty("target_branch")
        private String targetBranch;
    }

    @Data
    @JsonIgnoreProperties(ignoreUnknown = true)
    public static class MergeRequestNoteAttributes {
        private String note;

        @JsonProperty("noteable_type")
        private String noteableType;

        // 라인 코멘트일 경우
        @JsonProperty("position")
        private Position position;

        @Data
        @JsonIgnoreProperties(ignoreUnknown = true)
        public static class Position {
            @JsonProperty("base_sha")
            private String baseSha;

            @JsonProperty("head_sha")
            private String headSha;

            @JsonProperty("start_sha")
            private String startSha;

            @JsonProperty("new_path")
            private String newPath;

            @JsonProperty("old_path")
            private String oldPath;

            @JsonProperty("new_line")
            private Integer newLine;

            @JsonProperty("old_line")
            private Integer oldLine;
        }
    }

    /**
     * 라인 코멘트인지 확인
     */
    public boolean isLineComment() {
        return objectAttributes != null &&
               objectAttributes.getPosition() != null &&
               objectAttributes.getPosition().getNewLine() != null;
    }
}
