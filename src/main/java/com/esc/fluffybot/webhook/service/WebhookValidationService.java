package com.esc.fluffybot.webhook.service;

import com.esc.fluffybot.webhook.dto.GitLabWebhookPayload;
import org.springframework.stereotype.Service;

@Service
public class WebhookValidationService {

    public String validate(GitLabWebhookPayload payload) {
        if (!payload.isIssueHook()) {
            return "Not an issue hook";
        }

        if (!payload.isOpenOrUpdate()) {
            return "Issue action is not open or update";
        }

        if (payload.getProject() == null || payload.getProject().getId() == null) {
            return "Missing project information";
        }

        if (payload.getObjectAttributes() == null) {
            return "Missing object attributes";
        }

        if (payload.getIssueIid() == null) {
            return "Missing issue IID";
        }

        if (payload.getIssueTitle() == null) {
            return "Missing issue title";
        }

        return null;
    }
}
