package com.esc.fluffybot.webhook.dto;

import com.fasterxml.jackson.annotation.JsonProperty;
import com.fasterxml.jackson.databind.JsonNode;
import lombok.Data;

import java.util.List;

@Data
public class GitLabWebhookPayload {
    @JsonProperty("object_kind")
    private String objectKind;

    @JsonProperty("user")
    private UserInfo user;

    private ProjectInfo project;
    private List<AssigneeInfo> assignees;

    @JsonProperty("object_attributes")
    private ObjectAttributes objectAttributes;

    @JsonProperty("changes")
    private JsonNode changes;

    public DescriptionChange getDescriptionChange() {
        if (changes == null || changes.isNull() || changes.isMissingNode()) {
            return null;
        }
        JsonNode descNode = changes.get("description");
        if (descNode == null || descNode.isNull() || descNode.isMissingNode()) {
            return null;
        }
        DescriptionChange descChange = new DescriptionChange();
        JsonNode prevNode = descNode.get("previous");
        JsonNode currNode = descNode.get("current");
        if (prevNode != null && !prevNode.isNull()) {
            descChange.setPrevious(prevNode.asText());
        }
        if (currNode != null && !currNode.isNull()) {
            descChange.setCurrent(currNode.asText());
        }
        return descChange;
    }

    public boolean isIssueHook() {
        return "issue".equals(objectKind);
    }

    public boolean isOpenOrUpdate() {
        if (objectAttributes == null || objectAttributes.getAction() == null) {
            return false;
        }
        String action = objectAttributes.getAction();
        // Only accept "open" or "update" actions
        // Explicitly reject "close" and "reopen" to prevent triggering on issue state changes
        return "open".equals(action) || "update".equals(action);
    }

    public boolean isCloseAction() {
        if (objectAttributes == null || objectAttributes.getAction() == null) {
            return false;
        }
        String action = objectAttributes.getAction();
        return "close".equals(action);
    }

    public boolean isReopenAction() {
        if (objectAttributes == null || objectAttributes.getAction() == null) {
            return false;
        }
        String action = objectAttributes.getAction();
        return "reopen".equals(action);
    }

    public boolean hasAssignee(String username) {
        if (assignees == null || assignees.isEmpty()) {
            return false;
        }
        return assignees.stream()
            .anyMatch(assignee -> username.equals(assignee.getUsername()));
    }

    public Long getIssueIid() {
        return objectAttributes != null ? objectAttributes.getIid() : null;
    }

    public String getIssueTitle() {
        return objectAttributes != null ? objectAttributes.getTitle() : null;
    }

    public String getIssueDescription() {
        return objectAttributes != null ? objectAttributes.getDescription() : null;
    }

    public String getTaskDescription() {
        StringBuilder sb = new StringBuilder();
        if (getIssueTitle() != null) {
            sb.append("# ").append(getIssueTitle()).append("\n\n");
        }
        if (getIssueDescription() != null) {
            sb.append(getIssueDescription());
        }
        return sb.toString().trim();
    }

    public boolean hasDescriptionChange() {
        if (changes == null || changes.isNull() || changes.isMissingNode()) {
            return false;
        }
        JsonNode descriptionChange = changes.get("description");
        return descriptionChange != null && !descriptionChange.isNull() && !descriptionChange.isMissingNode();
    }

}
