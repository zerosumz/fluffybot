package com.esc.fluffybot.webhook.dto;

import lombok.AllArgsConstructor;
import lombok.Data;

@Data
@AllArgsConstructor
public class WebhookResponse {
    private String status;
    private String message;

    public static WebhookResponse accepted(String message) {
        return new WebhookResponse("accepted", message);
    }

    public static WebhookResponse ignored(String message) {
        return new WebhookResponse("ignored", message);
    }
}
