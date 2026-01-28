package com.esc.fluffybot.config;

import jakarta.validation.constraints.NotBlank;
import lombok.Data;
import org.springframework.boot.context.properties.ConfigurationProperties;
import org.springframework.stereotype.Component;
import org.springframework.validation.annotation.Validated;

@Data
@Validated
@Component
@ConfigurationProperties(prefix = "fluffybot.gitlab")
public class GitLabProperties {
    @NotBlank
    private String url;

    @NotBlank
    private String token;

    @NotBlank
    private String botUsername = "fluffybot";
}
