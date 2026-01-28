package com.esc.fluffybot.gitlab.exception;

public class GitLabApiException extends RuntimeException {
    public GitLabApiException(String message) {
        super(message);
    }
}
