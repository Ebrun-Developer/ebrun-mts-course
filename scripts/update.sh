#!/usr/bin/env bash
# update.sh - 检查 ebrun-mts-course Skill 是否有新版本
# 用法:
#   bash update.sh                                      # 默认输出 JSON 结果
#   bash update.sh --json                               # 输出 JSON 结果
#   bash update.sh --table                              # 输出文本结果
#   bash update.sh --timeout 10 --retries 3            # 调整超时与重试
#   bash update.sh --version-url <url>                 # 自定义版本接口地址

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="$SCRIPT_DIR/../references/config.json"
CACHE_FILE="${TMPDIR:-/tmp}/ebrun-mts-course-version-cache.json"
SKILL_NAME="ebrun-mts-course"
VERSION_API_URL="https://www.ebrun.com/_index/ClaudeCode/SkillJson/skill_version.json"
DEFAULT_TIMEOUT=10
DEFAULT_RETRIES=3
DEFAULT_CHECK_INTERVAL_HOURS=24
ALLOWED_DOMAINS=("www.ebrun.com" "api.ebrun.com" "github.com" "raw.githubusercontent.com" "gitee.com")
RETRYABLE_STATUS_CODES=(429 500 502 503 504)

EXIT_USAGE_ERROR=2
EXIT_SECURITY_ERROR=3
EXIT_REQUEST_ERROR=4
EXIT_NOT_FOUND=5
EXIT_FORBIDDEN=6
EXIT_JSON_ERROR=7

log_error() { echo "[ERROR] $*" >&2; }
log_warn() { echo "[WARN] $*" >&2; }

contains_value() {
    local value="$1"
    shift
    local item
    for item in "$@"; do
        if [ "$item" = "$value" ]; then
            return 0
        fi
    done
    return 1
}

check_deps() {
    if ! command -v curl >/dev/null 2>&1; then
        log_error "需要 curl 命令，请先安装 curl"
        exit "$EXIT_USAGE_ERROR"
    fi
    if ! command -v jq >/dev/null 2>&1; then
        log_error "需要 jq 命令，请先安装 jq"
        exit "$EXIT_USAGE_ERROR"
    fi
}

is_safe_url() {
    local url="$1"
    if [[ ! "$url" =~ ^https:// ]]; then
        return 1
    fi
    local host
    host=$(echo "$url" | sed -E 's|^https://([^/]+).*|\1|')
    local domain
    for domain in "${ALLOWED_DOMAINS[@]}"; do
        if [[ "$host" == "$domain" ]] || [[ "$host" == *".$domain" ]]; then
            return 0
        fi
    done
    return 1
}

validate_positive_int() {
    local value="$1"
    local arg_name="$2"
    if ! [[ "$value" =~ ^[0-9]+$ ]] || [ "$value" -le 0 ]; then
        log_error "参数错误: $arg_name 必须大于 0"
        exit "$EXIT_USAGE_ERROR"
    fi
}

validate_url() {
    local url="$1"
    local label="$2"
    if [ -z "$url" ]; then
        log_error "参数错误: $label 不能为空"
        exit "$EXIT_USAGE_ERROR"
    fi
    if ! is_safe_url "$url"; then
        log_error "安全性风险: 非授权地址 -> $url"
        exit "$EXIT_SECURITY_ERROR"
    fi
}

read_local_config() {
    if [ ! -f "$CONFIG_FILE" ]; then
        log_error "未找到本地配置文件: $CONFIG_FILE"
        exit "$EXIT_NOT_FOUND"
    fi

    local current_version
    current_version=$(jq -r '._meta.version // ""' "$CONFIG_FILE")
    if [ -z "$current_version" ]; then
        log_error "本地 config.json 缺少 _meta.version"
        exit "$EXIT_JSON_ERROR"
    fi

    local interval_hours
    interval_hours=$(jq -r '.check_interval_hours // empty' "$CONFIG_FILE")
    if [ -z "$interval_hours" ] || ! jq -e '(.check_interval_hours | type == "number") and (.check_interval_hours > 0)' "$CONFIG_FILE" >/dev/null 2>&1; then
        log_error "本地 config.json 中 check_interval_hours 必须大于 0"
        exit "$EXIT_JSON_ERROR"
    fi
}

get_config_field() {
    local jq_expr="$1"
    jq -r "$jq_expr // \"\"" "$CONFIG_FILE"
}

get_check_interval_seconds() {
    local interval_hours
    interval_hours=$(get_config_field '.check_interval_hours')
    awk -v h="$interval_hours" 'BEGIN { s=int(h * 3600); if (s < 1) s = 1; print s }'
}

read_cache_file() {
    if [ ! -f "$CACHE_FILE" ]; then
        echo '{}'
        return 0
    fi
    if ! jq -e 'type == "object"' "$CACHE_FILE" >/dev/null 2>&1; then
        echo '{}'
        return 0
    fi
    cat "$CACHE_FILE"
}

persist_check_cache() {
    local version_api_url="$1"
    local last_check_time="$2"
    local last_known_version="$3"
    local last_check_source="$4"
    local last_update_available="$5"
    local last_version_file_url="$6"

    if [ -z "$last_known_version" ] || [ "$last_known_version" = "unknown" ]; then
        return 0
    fi

    jq -n \
        --arg version_api_url "$version_api_url" \
        --argjson last_check_time "$last_check_time" \
        --arg last_known_version "$last_known_version" \
        --arg last_check_source "$last_check_source" \
        --argjson last_update_available "$last_update_available" \
        --arg last_version_file_url "$last_version_file_url" \
        '{
            version_api_url: $version_api_url,
            last_check_time: $last_check_time,
            last_known_version: $last_known_version,
            last_check_source: $last_check_source,
            last_update_available: $last_update_available,
            last_version_file_url: $last_version_file_url
        }' > "$CACHE_FILE"
}

http_error_message() {
    local status_code="$1"
    case "$status_code" in
        403) echo "版本接口请求被拒绝: HTTP 403" ;;
        404) echo "版本接口不存在: HTTP 404" ;;
        503) echo "版本接口暂时不可用: HTTP 503，可稍后重试" ;;
        *) echo "版本接口请求失败: HTTP $status_code" ;;
    esac
}

http_error_exit_code() {
    local status_code="$1"
    case "$status_code" in
        403) return "$EXIT_FORBIDDEN" ;;
        404) return "$EXIT_NOT_FOUND" ;;
        *) return "$EXIT_REQUEST_ERROR" ;;
    esac
}

network_error_message() {
    local curl_code="$1"
    case "$curl_code" in
        28) echo "版本接口请求超时，请稍后重试" ;;
        *) echo "版本接口请求失败: curl exit code $curl_code" ;;
    esac
}

is_retryable_http() {
    local status_code="$1"
    contains_value "$status_code" "${RETRYABLE_STATUS_CODES[@]}"
}

fetch_json() {
    local url="$1"
    local timeout="$2"
    local retries="$3"

    validate_url "$url" "--version-url"

    local attempt=1
    while [ "$attempt" -le "$retries" ]; do
        local tmp_body
        tmp_body=$(mktemp)
        local curl_code http_code message

        set +e
        http_code=$(curl -sS -L -o "$tmp_body" -w "%{http_code}" --max-time "$timeout" \
            -H "User-Agent: Mozilla/5.0 (EbrunMtsCourseUpdate/1.0)" \
            -H "Accept: application/json, text/plain, */*" \
            -H "Referer: https://www.ebrun.com/" \
            "$url")
        curl_code=$?
        set -e

        if [ "$curl_code" -eq 0 ] && [ "$http_code" = "200" ]; then
            if ! jq -e 'type == "object"' "$tmp_body" >/dev/null 2>&1; then
                rm -f "$tmp_body"
                log_error "版本接口格式异常: 顶层必须是对象"
                exit "$EXIT_JSON_ERROR"
            fi
            cat "$tmp_body"
            rm -f "$tmp_body"
            return 0
        fi

        if [ "$curl_code" -ne 0 ]; then
            message=$(network_error_message "$curl_code")
            rm -f "$tmp_body"
            if [ "$curl_code" -eq 28 ] && [ "$attempt" -lt "$retries" ]; then
                log_warn "$message. 第 $attempt 次请求失败，准备重试..."
                sleep "$(( attempt < 2 ? attempt : 2 ))"
                attempt=$((attempt + 1))
                continue
            fi
            log_error "$message"
            return "$EXIT_REQUEST_ERROR"
        fi

        message=$(http_error_message "$http_code")
        rm -f "$tmp_body"
        if is_retryable_http "$http_code" && [ "$attempt" -lt "$retries" ]; then
            log_warn "$message. 第 $attempt 次请求失败，准备重试..."
            sleep "$(( attempt < 2 ? attempt : 2 ))"
            attempt=$((attempt + 1))
            continue
        fi
        log_error "$message"
        http_error_exit_code "$http_code"
        return $?
    done

    log_error "版本接口请求失败: 未知错误"
    return "$EXIT_REQUEST_ERROR"
}

build_repo_config_file_urls() {
    local repo_url="$1"
    if [[ ! "$repo_url" =~ ^https://(github\.com|gitee\.com)/([^/]+)/([^/]+)$ ]]; then
        return 0
    fi

    local host="${BASH_REMATCH[1]}"
    local owner="${BASH_REMATCH[2]}"
    local repo="${BASH_REMATCH[3]}"
    repo="${repo%.git}"

    if [ "$host" = "github.com" ]; then
        printf '%s\n' \
            "https://raw.githubusercontent.com/$owner/$repo/main/references/config.json" \
            "https://raw.githubusercontent.com/$owner/$repo/master/references/config.json"
    else
        printf '%s\n' \
            "https://gitee.com/$owner/$repo/raw/main/references/config.json" \
            "https://gitee.com/$owner/$repo/raw/master/references/config.json"
    fi
}

fetch_repo_version_info() {
    local timeout="$1"
    local retries="$2"
    local errors=()
    local repo_url source_name candidate_url remote_json remote_version

    for source_name in github_config_json gitee_config_json; do
        if [ "$source_name" = "github_config_json" ]; then
            repo_url=$(get_config_field '.update_url_github')
        else
            repo_url=$(get_config_field '.update_url_gitee')
        fi

        [ -n "$repo_url" ] || continue

        while IFS= read -r candidate_url; do
            [ -n "$candidate_url" ] || continue
            set +e
            remote_json=$(fetch_json "$candidate_url" "$timeout" "$retries")
            local rc=$?
            set -e
            if [ "$rc" -eq 0 ]; then
                remote_version=$(jq -r '._meta.version // ""' <<<"$remote_json")
                if [ -z "$remote_version" ]; then
                    errors+=("$candidate_url: 远端 config.json 缺少 _meta.version")
                    continue
                fi
                jq -n \
                    --arg check_source "$source_name" \
                    --arg remote_version "$remote_version" \
                    --arg version_file_url "$candidate_url" \
                    '{check_source: $check_source, remote_version: $remote_version, version_file_url: $version_file_url}'
                return 0
            fi
            errors+=("$candidate_url: 请求失败")
        done < <(build_repo_config_file_urls "$repo_url")
    done

    if [ "${#errors[@]}" -eq 0 ]; then
        return 1
    fi

    printf '%s' "$(IFS='；'; echo "${errors[*]}")"
    return 1
}

check_url_reachable() {
    local url="$1"
    local timeout="$2"
    [ -n "$url" ] || return 1
    is_safe_url "$url" || return 1
    curl -I -L -sS --max-time "$timeout" "$url" >/dev/null 2>&1
}

print_table() {
    local json="$1"
    jq -r '
        "Skill 版本检查结果",
        "- skill_name: \(.skill_name)",
        "- current_version: \(.current_version)",
        "- latest_version: \(.latest_version)",
        "- update_available: \(.update_available)",
        "- check_source: \(.check_source)",
        "- status: \(.status)",
        "- message: \(.message)",
        (if .update_url_github != "" then "- update_url_github: \(.update_url_github)" else empty end),
        (if .update_url_gitee != "" then "- update_url_gitee: \(.update_url_gitee)" else empty end),
        (if (.version_file_url // "") != "" then "- version_file_url: \(.version_file_url)" else empty end),
        (if has("remote_check_error") then "- remote_check_error: \(.remote_check_error)" else empty end),
        (if has("repo_version_check_error") then "- repo_version_check_error: \(.repo_version_check_error)" else empty end)
    ' <<< "$json"
}

main() {
    check_deps
    read_local_config

    local output_format="json"
    local force_check="false"
    local version_url="$VERSION_API_URL"
    local timeout="$DEFAULT_TIMEOUT"
    local retries="$DEFAULT_RETRIES"

    while [ $# -gt 0 ]; do
        case "$1" in
            --json)
                output_format="json"
                shift
                ;;
            --table)
                output_format="table"
                shift
                ;;
            --force)
                force_check="true"
                shift
                ;;
            --version-url)
                [ $# -ge 2 ] || { log_error "参数错误: --version-url 缺少值"; exit "$EXIT_USAGE_ERROR"; }
                version_url="$2"
                shift 2
                ;;
            --timeout)
                [ $# -ge 2 ] || { log_error "参数错误: --timeout 缺少值"; exit "$EXIT_USAGE_ERROR"; }
                timeout="$2"
                shift 2
                ;;
            --retries)
                [ $# -ge 2 ] || { log_error "参数错误: --retries 缺少值"; exit "$EXIT_USAGE_ERROR"; }
                retries="$2"
                shift 2
                ;;
            --help|-h)
                sed -n '2,7p' "$0"
                exit 0
                ;;
            *)
                log_error "参数错误: 不支持的参数 -> $1"
                exit "$EXIT_USAGE_ERROR"
                ;;
        esac
    done

    validate_positive_int "$timeout" "--timeout"
    validate_positive_int "$retries" "--retries"
    validate_url "$version_url" "--version-url"

    local local_current_version update_url_github update_url_gitee check_interval_hours
    local_current_version=$(get_config_field '._meta.version')
    update_url_github=$(get_config_field '.update_url_github')
    update_url_gitee=$(get_config_field '.update_url_gitee')
    check_interval_hours=$(get_config_field '.check_interval_hours')

    local now_ts cache_json cached_version_api_url last_check_time last_known_version last_check_source
    now_ts=$(date +%s)
    cache_json=$(read_cache_file)
    cached_version_api_url=$(jq -r '.version_api_url // ""' <<<"$cache_json")
    last_check_time=$(jq -r '.last_check_time // 0' <<<"$cache_json")
    last_known_version=$(jq -r '.last_known_version // ""' <<<"$cache_json")
    last_check_source=$(jq -r '.last_check_source // ""' <<<"$cache_json")

    if [ "$force_check" != "true" ] && [ "$cached_version_api_url" = "$version_url" ] && [ "$last_check_time" -gt 0 ] && [ -n "$last_known_version" ] && [ -n "$last_check_source" ]; then
        local interval_seconds remaining_seconds
        interval_seconds=$(get_check_interval_seconds)
        if [ $(( now_ts - last_check_time )) -lt "$interval_seconds" ]; then
            remaining_seconds=$(( interval_seconds - (now_ts - last_check_time) ))
            local cached_result
            cached_result=$(jq -n \
                --arg skill_name "$SKILL_NAME" \
                --arg current_version "$local_current_version" \
                --arg latest_version "$last_known_version" \
                --arg check_source "$last_check_source" \
                --arg status "cached" \
                --arg version_api_url "$version_url" \
                --arg version_file_url "$(jq -r '.last_version_file_url // ""' <<<"$cache_json")" \
                --arg update_url_github "$update_url_github" \
                --arg update_url_gitee "$update_url_gitee" \
                --arg message "未到检查间隔，返回上次缓存结果" \
                --argjson update_available "$(jq '.last_update_available // false' <<<"$cache_json")" \
                --argjson last_check_time "$last_check_time" \
                --argjson check_interval_hours "$check_interval_hours" \
                --argjson remaining_seconds "$remaining_seconds" \
                '{
                    skill_name: $skill_name,
                    current_version: $current_version,
                    latest_version: $latest_version,
                    update_available: $update_available,
                    check_source: $check_source,
                    status: $status,
                    version_api_url: $version_api_url,
                    version_file_url: $version_file_url,
                    update_url_github: $update_url_github,
                    update_url_gitee: $update_url_gitee,
                    last_check_time: $last_check_time,
                    check_interval_hours: $check_interval_hours,
                    remaining_seconds: $remaining_seconds,
                    message: $message
                }')
            if [ "$output_format" = "table" ]; then
                print_table "$cached_result"
            else
                jq . <<<"$cached_result"
            fi
            return 0
        fi
    fi

    local result_json remote_json remote_version remote_error repo_info repo_error
    set +e
    remote_json=$(fetch_json "$version_url" "$timeout" "$retries")
    local remote_rc=$?
    set -e

    if [ "$remote_rc" -eq 0 ]; then
        remote_version=$(jq -r --arg skill_name "$SKILL_NAME" '.[$skill_name] // ""' <<<"$remote_json")
        if [ -z "$remote_version" ]; then
            remote_rc=1
            remote_error="版本接口未返回 $SKILL_NAME 字段"
        else
        result_json=$(jq -n \
            --arg skill_name "$SKILL_NAME" \
            --arg current_version "$local_current_version" \
            --arg latest_version "$remote_version" \
            --arg check_source "remote_api" \
            --arg status "ok" \
            --arg version_api_url "$version_url" \
            --arg update_url_github "$update_url_github" \
            --arg update_url_gitee "$update_url_gitee" \
            --arg message "$( [ "$remote_version" = "$local_current_version" ] && echo "检测完成" || echo "检测到新版本: $remote_version" )" \
            --argjson update_available "$( [ "$remote_version" = "$local_current_version" ] && echo false || echo true )" \
            '{
                skill_name: $skill_name,
                current_version: $current_version,
                latest_version: $latest_version,
                update_available: $update_available,
                check_source: $check_source,
                status: $status,
                version_api_url: $version_api_url,
                update_url_github: $update_url_github,
                update_url_gitee: $update_url_gitee,
                message: $message
            }')
        fi
    else
        remote_error="版本接口不可用"
    fi

    if [ -z "${result_json:-}" ]; then
        : "${remote_error:=版本接口不可用}"
        set +e
        repo_info=$(fetch_repo_version_info "$timeout" "$retries")
        local repo_rc=$?
        set -e
        if [ "$repo_rc" -eq 0 ]; then
            remote_version=$(jq -r '.remote_version' <<<"$repo_info")
            result_json=$(jq -n \
                --arg skill_name "$SKILL_NAME" \
                --arg current_version "$local_current_version" \
                --arg latest_version "$remote_version" \
                --arg check_source "$(jq -r '.check_source' <<<"$repo_info")" \
                --arg status "degraded" \
                --arg version_api_url "$version_url" \
                --arg version_file_url "$(jq -r '.version_file_url' <<<"$repo_info")" \
                --arg update_url_github "$update_url_github" \
                --arg update_url_gitee "$update_url_gitee" \
                --arg remote_check_error "$remote_error" \
                --arg message "$( [ "$remote_version" = "$local_current_version" ] && echo "版本接口不可用，已降级到远端仓库 config.json；当前未发现版本变化" || echo "版本接口不可用，已降级到远端仓库 config.json；检测到版本不一致: $local_current_version -> $remote_version" )" \
                --argjson update_available "$( [ "$remote_version" = "$local_current_version" ] && echo false || echo true )" \
                '{
                    skill_name: $skill_name,
                    current_version: $current_version,
                    latest_version: $latest_version,
                    update_available: $update_available,
                    check_source: $check_source,
                    status: $status,
                    version_api_url: $version_api_url,
                    version_file_url: $version_file_url,
                    update_url_github: $update_url_github,
                    update_url_gitee: $update_url_gitee,
                    remote_check_error: $remote_check_error,
                    message: $message
                }')
        else
            repo_error="${repo_info:-无法从远端仓库读取 references/config.json}"
            result_json=$(jq -n \
                --arg skill_name "$SKILL_NAME" \
                --arg current_version "$local_current_version" \
                --arg latest_version "unknown" \
                --arg check_source "unavailable" \
                --arg status "degraded" \
                --arg version_api_url "$version_url" \
                --arg update_url_github "$update_url_github" \
                --arg update_url_gitee "$update_url_gitee" \
                --arg remote_check_error "$remote_error" \
                --arg repo_version_check_error "$repo_error" \
                --arg message "版本接口不可用，且无法从远端仓库读取 references/config.json，当前无法判断是否有新版本" \
                --argjson update_available false \
                --argjson update_url_github_reachable "$(check_url_reachable "$update_url_github" "$timeout" && echo true || echo false)" \
                --argjson update_url_gitee_reachable "$(check_url_reachable "$update_url_gitee" "$timeout" && echo true || echo false)" \
                '{
                    skill_name: $skill_name,
                    current_version: $current_version,
                    latest_version: $latest_version,
                    update_available: $update_available,
                    check_source: $check_source,
                    status: $status,
                    version_api_url: $version_api_url,
                    update_url_github: $update_url_github,
                    update_url_gitee: $update_url_gitee,
                    update_url_github_reachable: $update_url_github_reachable,
                    update_url_gitee_reachable: $update_url_gitee_reachable,
                    remote_check_error: $remote_check_error,
                    repo_version_check_error: $repo_version_check_error,
                    message: $message
                }')
        fi
    fi

    persist_check_cache \
        "$version_url" \
        "$now_ts" \
        "$(jq -r '.latest_version' <<<"$result_json")" \
        "$(jq -r '.check_source' <<<"$result_json")" \
        "$(jq -r '.update_available' <<<"$result_json")" \
        "$(jq -r '.version_file_url // ""' <<<"$result_json")"

    if [ "$output_format" = "table" ]; then
        print_table "$result_json"
    else
        jq . <<<"$result_json"
    fi
}

main "$@"
