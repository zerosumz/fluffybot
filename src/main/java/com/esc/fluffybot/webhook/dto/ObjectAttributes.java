package com.esc.fluffybot.webhook.dto;

import lombok.Data;

import java.util.List;
import java.util.stream.Collectors;

@Data
public class ObjectAttributes {
    private Long id;
    private Long iid;
    private String title;
    private String description;
    private String state;
    private String action;
    private List<LabelInfo> labels;

    /**
     * 라벨 이름 목록을 반환합니다.
     * @return 라벨 이름 리스트
     */
    public List<String> getLabelNames() {
        if (labels == null) {
            return List.of();
        }
        return labels.stream()
                .map(LabelInfo::getName)
                .collect(Collectors.toList());
    }

    /**
     * 특정 라벨이 있는지 확인합니다.
     * @param labelName 라벨 이름
     * @return 라벨 존재 여부
     */
    public boolean hasLabel(String labelName) {
        if (labels == null) {
            return false;
        }
        return labels.stream()
                .anyMatch(label -> labelName.equals(label.getName()));
    }
}
