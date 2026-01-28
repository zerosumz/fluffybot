package com.esc.fluffybot.webhook.dto;

import lombok.Data;

@Data
public class ObjectAttributes {
    private Long id;
    private Long iid;
    private String title;
    private String description;
    private String state;
    private String action;
}
