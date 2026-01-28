package com.esc.fluffybot.webhook.dto;

import com.fasterxml.jackson.annotation.JsonProperty;
import lombok.Data;
import lombok.NoArgsConstructor;

@Data
@NoArgsConstructor
public class NoteHookPayload {

    @JsonProperty("object_kind")
    private String objectKind;

    @JsonProperty("user")
    private UserInfo user;

    @JsonProperty("project")
    private ProjectInfo project;

    @JsonProperty("object_attributes")
    private NoteObjectAttributes objectAttributes;

    @JsonProperty("issue")
    private IssueInfo issue;
}
