package com.esc.fluffybot.config;

import jakarta.validation.constraints.NotBlank;
import lombok.Data;
import org.springframework.boot.context.properties.ConfigurationProperties;
import org.springframework.stereotype.Component;
import org.springframework.validation.annotation.Validated;

@Data
@Validated
@Component
@ConfigurationProperties(prefix = "fluffybot.worker")
public class WorkerProperties {
    @NotBlank
    private String namespace = "gitlab";

    @NotBlank
    private String image;

    @NotBlank
    private String anthropicApiKey;

    private int timeoutMinutes = 30;

    private String cpuRequest = "500m";
    private String cpuLimit = "2";
    private String memoryRequest = "2Gi";
    private String memoryLimit = "4Gi";
}
