package com.esc.fluffybot.webhook.dto;

import com.fasterxml.jackson.annotation.JsonProperty;
import lombok.Data;
import lombok.NoArgsConstructor;

@Data
@NoArgsConstructor
public class NoteObjectAttributes {

    @JsonProperty("id")
    private Long id;

    @JsonProperty("note")
    private String note;

    @JsonProperty("noteable_type")
    private String noteableType;

    @JsonProperty("author_id")
    private Long authorId;

    @JsonProperty("created_at")
    private String createdAt;

    @JsonProperty("updated_at")
    private String updatedAt;

    @JsonProperty("noteable_id")
    private Long noteableId;
}
