package com.esc.fluffybot.webhook.dto;

import com.fasterxml.jackson.annotation.JsonProperty;
import lombok.Data;

@Data
public class LabelInfo {
    private Long id;
    private String name;
    private String color;
    private String description;

    @JsonProperty("text_color")
    private String textColor;
}
