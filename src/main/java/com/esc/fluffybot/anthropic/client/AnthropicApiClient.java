package com.esc.fluffybot.anthropic.client;

import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.ai.chat.model.ChatModel;
import org.springframework.ai.chat.prompt.Prompt;
import org.springframework.stereotype.Service;
import reactor.core.publisher.Mono;
import reactor.core.scheduler.Schedulers;

@Slf4j
@Service
@RequiredArgsConstructor
public class AnthropicApiClient {

    private final ChatModel chatModel;

    public Mono<String> chat(String prompt) {
        return Mono.fromCallable(() -> {
                log.debug("Calling Anthropic API via Spring AI");
                return chatModel.call(new Prompt(prompt)).getResult().getOutput().getContent();
            })
            .subscribeOn(Schedulers.boundedElastic())
            .doOnSuccess(v -> log.debug("Anthropic API call successful"))
            .doOnError(e -> log.error("Failed to call Anthropic API: {}", e.getMessage()));
    }
}
