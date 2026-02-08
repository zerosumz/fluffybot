package com.esc.fluffybot.webhook.dto;

import lombok.Data;

@Data
public class DescriptionChange {
    private String previous;
    private String current;

    public boolean hasChange() {
        return previous != null && current != null && !previous.equals(current);
    }
}
