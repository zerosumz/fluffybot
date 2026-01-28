package com.esc.fluffybot.gitlab.client;

import com.esc.fluffybot.gitlab.exception.GitLabApiException;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.core.ParameterizedTypeReference;
import org.springframework.stereotype.Service;
import org.springframework.web.reactive.function.client.WebClient;
import reactor.core.publisher.Mono;

import java.util.List;
import java.util.Map;

/**
 * GitLab Wiki API 클라이언트
 *
 * GitLab Wiki API를 통해 프로젝트 위키 페이지를 조회하고 관리합니다.
 */
@Slf4j
@Service
@RequiredArgsConstructor
public class GitLabWikiClient {

    private final WebClient gitLabWebClient;

    /**
     * 프로젝트의 모든 위키 페이지 목록 조회
     *
     * @param projectId GitLab 프로젝트 ID
     * @return 위키 페이지 목록 (slug, title 포함)
     */
    public Mono<List<Map<String, Object>>> listWikiPages(Long projectId) {
        String uri = String.format("/api/v4/projects/%d/wikis", projectId);

        return gitLabWebClient.get()
            .uri(uri)
            .retrieve()
            .onStatus(
                status -> status.is4xxClientError() || status.is5xxServerError(),
                response -> response.bodyToMono(String.class)
                    .flatMap(body -> {
                        log.error("GitLab API error: status={}, body={}", response.statusCode(), body);
                        return Mono.error(new GitLabApiException(
                            "Failed to list wiki pages: " + response.statusCode()
                        ));
                    })
            )
            .bodyToMono(new ParameterizedTypeReference<List<Map<String, Object>>>() {})
            .doOnSuccess(pages -> log.debug("Retrieved {} wiki pages for project={}",
                pages != null ? pages.size() : 0, projectId))
            .onErrorResume(e -> {
                log.error("Failed to list wiki pages: {}", e.getMessage());
                return Mono.just(List.of());
            });
    }

    /**
     * 특정 위키 페이지 조회
     *
     * @param projectId GitLab 프로젝트 ID
     * @param slug 위키 페이지 slug (URL-safe 제목)
     * @return 위키 페이지 정보 (content, title, format 포함)
     */
    public Mono<Map<String, Object>> getWikiPage(Long projectId, String slug) {
        String uri = String.format("/api/v4/projects/%d/wikis/%s", projectId, slug);

        return gitLabWebClient.get()
            .uri(uri)
            .retrieve()
            .onStatus(
                status -> status.is4xxClientError() || status.is5xxServerError(),
                response -> response.bodyToMono(String.class)
                    .flatMap(body -> {
                        log.error("GitLab API error: status={}, body={}", response.statusCode(), body);
                        return Mono.error(new GitLabApiException(
                            "Failed to get wiki page: " + response.statusCode()
                        ));
                    })
            )
            .bodyToMono(new ParameterizedTypeReference<Map<String, Object>>() {})
            .doOnSuccess(page -> log.debug("Retrieved wiki page: project={}, slug={}", projectId, slug))
            .onErrorResume(e -> {
                log.warn("Failed to get wiki page {}: {}", slug, e.getMessage());
                return Mono.empty();
            });
    }

    /**
     * 위키 페이지 생성
     *
     * @param projectId GitLab 프로젝트 ID
     * @param title 페이지 제목
     * @param content 페이지 내용 (Markdown)
     * @param format 내용 형식 (기본값: markdown)
     * @return 생성된 위키 페이지 정보
     */
    public Mono<Map<String, Object>> createWikiPage(
            Long projectId,
            String title,
            String content,
            String format) {

        String uri = String.format("/api/v4/projects/%d/wikis", projectId);

        Map<String, String> request = Map.of(
            "title", title,
            "content", content,
            "format", format != null ? format : "markdown"
        );

        return gitLabWebClient.post()
            .uri(uri)
            .bodyValue(request)
            .retrieve()
            .onStatus(
                status -> status.is4xxClientError() || status.is5xxServerError(),
                response -> response.bodyToMono(String.class)
                    .flatMap(body -> {
                        log.error("GitLab API error: status={}, body={}", response.statusCode(), body);
                        return Mono.error(new GitLabApiException(
                            "Failed to create wiki page: " + response.statusCode()
                        ));
                    })
            )
            .bodyToMono(new ParameterizedTypeReference<Map<String, Object>>() {})
            .doOnSuccess(page -> log.info("Created wiki page: project={}, title={}", projectId, title))
            .onErrorResume(e -> {
                log.error("Failed to create wiki page: {}", e.getMessage());
                return Mono.empty();
            });
    }

    /**
     * 위키 페이지 수정
     *
     * @param projectId GitLab 프로젝트 ID
     * @param slug 페이지 slug
     * @param title 새 제목 (선택)
     * @param content 새 내용
     * @param format 내용 형식 (기본값: markdown)
     * @return 수정된 위키 페이지 정보
     */
    public Mono<Map<String, Object>> updateWikiPage(
            Long projectId,
            String slug,
            String title,
            String content,
            String format) {

        String uri = String.format("/api/v4/projects/%d/wikis/%s", projectId, slug);

        Map<String, String> request = Map.of(
            "content", content,
            "format", format != null ? format : "markdown"
        );

        // title이 제공되면 추가
        if (title != null && !title.isEmpty()) {
            request = Map.of(
                "title", title,
                "content", content,
                "format", format != null ? format : "markdown"
            );
        }

        return gitLabWebClient.put()
            .uri(uri)
            .bodyValue(request)
            .retrieve()
            .onStatus(
                status -> status.is4xxClientError() || status.is5xxServerError(),
                response -> response.bodyToMono(String.class)
                    .flatMap(body -> {
                        log.error("GitLab API error: status={}, body={}", response.statusCode(), body);
                        return Mono.error(new GitLabApiException(
                            "Failed to update wiki page: " + response.statusCode()
                        ));
                    })
            )
            .bodyToMono(new ParameterizedTypeReference<Map<String, Object>>() {})
            .doOnSuccess(page -> log.info("Updated wiki page: project={}, slug={}", projectId, slug))
            .onErrorResume(e -> {
                log.error("Failed to update wiki page: {}", e.getMessage());
                return Mono.empty();
            });
    }

    /**
     * 모든 위키 페이지 내용을 조합하여 하나의 컨텍스트 문자열로 반환
     * Worker에서 Claude에게 전달할 프로젝트 컨텍스트를 수집합니다.
     *
     * @param projectId GitLab 프로젝트 ID
     * @return 모든 위키 페이지 내용을 포함한 컨텍스트 문자열
     */
    public Mono<String> getWikiContext(Long projectId) {
        return listWikiPages(projectId)
            .flatMap(pages -> {
                if (pages.isEmpty()) {
                    log.warn("No wiki pages found for project={}", projectId);
                    return Mono.just("");
                }

                // 각 페이지의 slug 추출
                List<String> slugs = pages.stream()
                    .map(page -> (String) page.get("slug"))
                    .filter(slug -> slug != null && !slug.isEmpty())
                    .toList();

                // 모든 페이지 내용 조회
                return fetchAllPageContents(projectId, slugs);
            });
    }

    /**
     * 여러 위키 페이지의 내용을 병렬로 조회하여 하나의 문자열로 결합
     */
    private Mono<String> fetchAllPageContents(Long projectId, List<String> slugs) {
        if (slugs.isEmpty()) {
            return Mono.just("");
        }

        return Mono.zip(
            slugs.stream()
                .map(slug -> getWikiPage(projectId, slug)
                    .map(page -> formatWikiPageForContext(page))
                    .defaultIfEmpty(""))
                .toList(),
            results -> {
                StringBuilder context = new StringBuilder("# 프로젝트 위키\n\n");
                for (Object result : results) {
                    if (result != null && !result.toString().isEmpty()) {
                        context.append(result.toString()).append("\n---\n\n");
                    }
                }
                return context.toString();
            }
        );
    }

    /**
     * 위키 페이지 정보를 컨텍스트용 포맷으로 변환
     */
    private String formatWikiPageForContext(Map<String, Object> page) {
        String title = (String) page.get("title");
        String content = (String) page.get("content");

        if (title == null || content == null) {
            return "";
        }

        return String.format("## %s\n\n%s\n", title, content);
    }
}
