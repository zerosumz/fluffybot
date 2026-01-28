package com.esc.fluffybot.config;

import org.springframework.ai.anthropic.AnthropicChatModel;
import org.springframework.ai.anthropic.AnthropicChatOptions;
import org.springframework.ai.anthropic.api.AnthropicApi;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;

@Configuration
public class AnthropicConfig {

    @Bean
    public AnthropicApi anthropicApi(AnthropicProperties properties) {
        return new AnthropicApi(properties.getApiUrl(), properties.getApiKey());
    }

    @Bean
    public AnthropicChatModel anthropicChatModel(
            AnthropicApi anthropicApi,
            AnthropicProperties properties) {

        AnthropicChatOptions options = AnthropicChatOptions.builder()
            .withModel(properties.getModel())
            .withMaxTokens(properties.getMaxTokens())
            .build();

        return new AnthropicChatModel(anthropicApi, options);
    }
}
