package com.esc.fluffybot.worker.exception;

public class PodCreationException extends RuntimeException {
    public PodCreationException(String message, Throwable cause) {
        super(message, cause);
    }
}
