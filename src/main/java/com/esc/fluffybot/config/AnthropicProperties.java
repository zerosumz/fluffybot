package com.esc.fluffybot.config;

import lombok.Data;
import org.springframework.boot.context.properties.ConfigurationProperties;
import org.springframework.stereotype.Component;

@Data
@Component
@ConfigurationProperties(prefix = "fluffybot.anthropic")
public class AnthropicProperties {

    private String apiKey;
    private String apiUrl = "https://api.anthropic.com";
    private String model = "claude-sonnet-4-20250514";
    private Integer maxTokens = 1024;
}
