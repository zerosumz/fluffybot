package com.esc.fluffybot.webhook.dto;

import lombok.Data;

@Data
public class IssueInfo {
    private Long iid;
    private String title;
    private String description;
}
