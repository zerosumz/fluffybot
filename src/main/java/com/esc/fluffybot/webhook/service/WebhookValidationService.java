package com.esc.fluffybot.webhook.service;

import com.esc.fluffybot.webhook.dto.GitLabWebhookPayload;
import org.springframework.stereotype.Service;

@Service
public class WebhookValidationService {

    public String validate(GitLabWebhookPayload payload) {
        if (!payload.isIssueHook()) {
            return "Not an issue hook";
        }

        // Explicitly reject close actions to prevent triggering on issue closure
        if (payload.isCloseAction()) {
            return "Issue is being closed - ignoring";
        }

        // Explicitly reject reopen actions to prevent duplicate Worker Jobs
        // When an issue is reopened and modified, "update" event will trigger separately
        if (payload.isReopenAction()) {
            return "Issue is being reopened - ignoring (description update will trigger separately)";
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
