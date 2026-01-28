package com.esc.fluffybot.webhook.dto;

import com.fasterxml.jackson.annotation.JsonProperty;
import lombok.Data;

@Data
public class ProjectInfo {
    private Long id;

    @JsonProperty("path_with_namespace")
    private String pathWithNamespace;

    @JsonProperty("git_http_url")
    private String gitHttpUrl;
}
