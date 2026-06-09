#!/usr/bin/env bash
# query_courses.sh - 查询马蹄社近期课程和月份课程表
# 用法:
#   bash query_courses.sh recent --json
#   bash query_courses.sh recent --table
#   bash query_courses.sh month --month 2026-06 --json
#   bash query_courses.sh month --relative current --json
#   bash query_courses.sh month --relative next --table

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CONFIG_FILE="$SCRIPT_DIR/../references/config.json"
WIDTH=72
DEFAULT_TIMEOUT=10

EXIT_USAGE_ERROR=2
EXIT_SECURITY_ERROR=3
EXIT_REQUEST_ERROR=4
EXIT_NOT_FOUND=5
EXIT_FORBIDDEN=6
EXIT_JSON_ERROR=7

log_error() { echo "[ERROR] $*" >&2; }

usage() {
    cat <<'EOF'
用法:
  bash query_courses.sh recent --json
  bash query_courses.sh recent --table
  bash query_courses.sh month --month 2026-06 --json
  bash query_courses.sh month --relative current --json
  bash query_courses.sh month --relative next --table
EOF
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
    [[ "$url" =~ ^https://([[:alnum:]-]+\.)*ebrun\.com(/|$) ]]
}

read_config_value() {
    local jq_expr="$1"
    jq -er "$jq_expr" "$CONFIG_FILE"
}

current_month() {
    date '+%Y-%m'
}

resolve_relative_month() {
    local relative="$1"
    local year month
    year="$(date '+%Y')"
    month="$(date '+%m')"

    case "$relative" in
        current)
            printf '%s-%s\n' "$year" "$month"
            ;;
        next)
            if [ "$month" = "12" ]; then
                printf '%04d-01\n' "$((year + 1))"
            else
                printf '%04d-%02d\n' "$year" "$((10#$month + 1))"
            fi
            ;;
        *)
            log_error "参数错误: --relative 只支持 current 或 next"
            exit "$EXIT_USAGE_ERROR"
            ;;
    esac
}

month_to_label() {
    local month="$1"
    local month_num="${month#*-}"
    printf '%d月\n' "$((10#$month_num))"
}

resolve_month_input() {
    local month="$1"
    local fallback_month
    fallback_month="$(current_month)"

    if [[ "$month" =~ ^[0-9]{4}-(0[1-9]|1[0-2])$ ]]; then
        jq -nc --arg requested_month "$month" --arg resolved_month "$month" '
            {
                requested_month: $requested_month,
                resolved_month: $resolved_month,
                month_input_valid: true,
                notice: ""
            }
        '
        return 0
    fi

    jq -nc --arg requested_month "$month" --arg resolved_month "$fallback_month" '
        {
            requested_month: $requested_month,
            resolved_month: $resolved_month,
            month_input_valid: false,
            notice: ("你提供的月份不正确，已为你展示当前月份（" + $resolved_month + "）课程。")
        }
    '
}

fetch_json() {
    local url="$1"
    if ! is_safe_url "$url"; then
        log_error "安全性风险: 非授权地址 -> $url"
        exit "$EXIT_SECURITY_ERROR"
    fi

    local response http_code body
    response="$(curl -sS -L --max-time "$DEFAULT_TIMEOUT" -w $'\n%{http_code}' \
        -H 'Accept: application/json, text/plain, */*' \
        -H 'Referer: https://www.ebrun.com/' \
        -H 'User-Agent: Mozilla/5.0 (EbrunMtsCourseShell/1.0)' \
        "$url")" || {
        log_error "网络请求失败，请稍后重试"
        exit "$EXIT_REQUEST_ERROR"
    }

    http_code="${response##*$'\n'}"
    body="${response%$'\n'*}"

    case "$http_code" in
        200) ;;
        403)
            log_error "请求被拒绝: HTTP 403"
            exit "$EXIT_FORBIDDEN"
            ;;
        404)
            log_error "资源不存在: HTTP 404"
            exit "$EXIT_NOT_FOUND"
            ;;
        503)
            log_error "服务暂时不可用: HTTP 503，可稍后重试"
            exit "$EXIT_REQUEST_ERROR"
            ;;
        *)
            log_error "请求失败: HTTP $http_code"
            exit "$EXIT_REQUEST_ERROR"
            ;;
    esac

    if ! jq empty >/dev/null 2>&1 <<<"$body"; then
        log_error "JSON 解析失败: 接口返回不是合法 JSON"
        exit "$EXIT_JSON_ERROR"
    fi

    printf '%s\n' "$body"
}

normalize_recent_json() {
    local raw_json="$1"
    jq -c '
        if type != "array" then
            error("近期课程顶层必须是数组")
        else
            map(
                {
                    title: ((.title // "") | tostring | gsub("[\r\n\t]"; " ") | split(" ") | map(select(length > 0)) | join(" ")),
                    url: ((.url // "") | tostring | gsub("[\r\n\t]"; " ") | split(" ") | map(select(length > 0)) | join(" ")),
                    status: (
                        ((.status // "") | tostring | gsub("[\r\n\t]"; " ") | split(" ") | map(select(length > 0)) | join(" "))
                        | if . == "" then "状态待更新" elif . == "立即报名" then "正在报名" else . end
                    ),
                    date_text: (
                        (((.date_text // .date // "") | tostring | gsub("[\r\n\t]"; " ") | split(" ") | map(select(length > 0)) | join(" ")))
                        | if . == "" then "未注明" else . end
                    ),
                    city: (
                        ((.city // "") | tostring | gsub("[\r\n\t]"; " ") | split(" ") | map(select(length > 0)) | join(" "))
                        | if . == "" then "未注明" else . end
                    ),
                    summary: (
                        ((.summary // "") | tostring | gsub("[\r\n\t]"; " ") | split(" ") | map(select(length > 0)) | join(" "))
                        | if . == "" then "未注明" else . end
                    ),
                    month: "",
                    tags: (if (.tags | type) == "array" then (.tags | join(",")) else ((.tags // "") | tostring) end)
                }
            )
        end
    ' <<<"$raw_json"
}

normalize_month_json() {
    local raw_json="$1"
    local month="$2"
    local month_label="$3"
    jq -c --arg month "$month" --arg month_label "$month_label" '
        if type != "object" then
            error("月份课程表顶层必须是对象")
        else
            (.[$month_label] // [])
            | if type != "array" then
                error($month_label + " 对应数据必须是数组")
              else
                map({
                    title: (
                        ((.title // "") | tostring | gsub("[\r\n\t]"; " ") | split(" ") | map(select(length > 0)) | join(" "))
                        | if . == "" then "未注明" else . end
                    ),
                    url: ((.url // "") | tostring | gsub("[\r\n\t]"; " ") | split(" ") | map(select(length > 0)) | join(" ")),
                    status: (
                        ((.status // "") | tostring | gsub("[\r\n\t]"; " ") | split(" ") | map(select(length > 0)) | join(" "))
                        | if . == "" then "状态待更新" elif . == "立即报名" then "正在报名" else . end
                    ),
                    date_text: (
                        (((.date_text // .date // "") | tostring | gsub("[\r\n\t]"; " ") | split(" ") | map(select(length > 0)) | join(" ")))
                        | if . == "" then "未注明" else . end
                    ),
                    city: (
                        ((.city // "") | tostring | gsub("[\r\n\t]"; " ") | split(" ") | map(select(length > 0)) | join(" "))
                        | if . == "" then "未注明" else . end
                    ),
                    summary: (
                        ((.summary // "") | tostring | gsub("[\r\n\t]"; " ") | split(" ") | map(select(length > 0)) | join(" "))
                        | if . == "" then "未注明" else . end
                    ),
                    month: $month,
                    tags: (if (.tags | type) == "array" then (.tags | join(",")) else ((.tags // "") | tostring) end)
                })
              end
        end
    ' <<<"$raw_json"
}

print_table() {
    local title="$1"
    local json="$2"
    local count
    count="$(jq 'length' <<<"$json")"
    if [ "$count" -eq 0 ]; then
        echo "暂无课程数据"
        return 0
    fi

    printf '\n┌%*s┐\n' $((WIDTH - 2)) '' | tr ' ' '─'
    printf '│  %-66s│\n' "$title"
    printf '├%*s┤\n' $((WIDTH - 2)) '' | tr ' ' '─'

    jq -r '
        to_entries[]
        | [.key + 1, .value.title, .value.status, .value.date_text, .value.city]
        | @tsv
    ' <<<"$json" | while IFS=$'\t' read -r idx title_value status_value date_value city_value; do
        printf '│  %2d. %-60s │\n' "$idx" "${title_value:0:60}"
        printf '│      状态: %-12s 时间: %-20s│\n' "${status_value:0:12}" "${date_value:0:20}"
        printf '│      地点: %-52s │\n' "${city_value:0:52}"
        if [ "$idx" -lt "$count" ]; then
            printf '├%*s┤\n' $((WIDTH - 2)) '' | tr ' ' '─'
        fi
    done

    printf '└%*s┘\n' $((WIDTH - 2)) '' | tr ' ' '─'
    printf '\n共 %s 条课程\n' "$count"
}

main() {
    check_deps

    if [ $# -lt 1 ]; then
        usage
        exit "$EXIT_USAGE_ERROR"
    fi

    case "${1:-}" in
        --help|-h)
            usage
            exit 0
            ;;
    esac

    local command="$1"
    shift

    local output_format="json"
    local month=""
    local relative=""

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
            --month)
                [ $# -ge 2 ] || { log_error "参数错误: --month 缺少值"; exit "$EXIT_USAGE_ERROR"; }
                month="$2"
                shift 2
                ;;
            --relative)
                [ $# -ge 2 ] || { log_error "参数错误: --relative 缺少值"; exit "$EXIT_USAGE_ERROR"; }
                relative="$2"
                shift 2
                ;;
            --help|-h)
                usage
                exit 0
                ;;
            *)
                log_error "参数错误: 不支持的参数 -> $1"
                exit "$EXIT_USAGE_ERROR"
                ;;
        esac
    done

    local api_url raw_json normalized_json month_label month_meta resolved_month month_notice month_input_valid requested_month
    case "$command" in
        recent)
            api_url="$(read_config_value '.data_source.recent_real_api_url')"
            raw_json="$(fetch_json "$api_url")"
            normalized_json="$(normalize_recent_json "$raw_json")"
            ;;
        month)
            if [ -n "$month" ] && [ -n "$relative" ]; then
                log_error "参数错误: --month 和 --relative 只能二选一"
                exit "$EXIT_USAGE_ERROR"
            fi
            if [ -z "$month" ] && [ -z "$relative" ]; then
                log_error "参数错误: month 命令必须传 --month 或 --relative"
                exit "$EXIT_USAGE_ERROR"
            fi
            if [ -n "$relative" ]; then
                month="$(resolve_relative_month "$relative")"
                month_meta="$(jq -nc --arg resolved_month "$month" '
                    {
                        requested_month: $resolved_month,
                        resolved_month: $resolved_month,
                        month_input_valid: true,
                        notice: ""
                    }
                ')"
            else
                month_meta="$(resolve_month_input "$month")"
            fi
            requested_month="$(jq -r '.requested_month' <<<"$month_meta")"
            resolved_month="$(jq -r '.resolved_month' <<<"$month_meta")"
            month_input_valid="$(jq -r '.month_input_valid' <<<"$month_meta")"
            month_notice="$(jq -r '.notice' <<<"$month_meta")"
            month_label="$(month_to_label "$resolved_month")"
            api_url="$(read_config_value '.data_source.monthly_real_api_url')"
            raw_json="$(fetch_json "$api_url")"
            normalized_json="$(normalize_month_json "$raw_json" "$resolved_month" "$month_label")"
            ;;
        *)
            log_error "参数错误: 不支持的命令 -> $command"
            exit "$EXIT_USAGE_ERROR"
            ;;
    esac

    if [ "$output_format" = "table" ]; then
        if [ "$command" = "recent" ]; then
            print_table "马蹄社近期课程" "$normalized_json"
        else
            if [ "$month_input_valid" = "false" ] && [ -n "$month_notice" ]; then
                printf '%s\n\n' "$month_notice"
            fi
            print_table "马蹄社课程表 $resolved_month" "$normalized_json"
        fi
        return 0
    fi

    if [ "$command" = "recent" ]; then
        jq . <<<"$normalized_json"
        return 0
    fi

    jq -n \
        --arg requested_month "$requested_month" \
        --arg resolved_month "$resolved_month" \
        --arg notice "$month_notice" \
        --argjson month_input_valid "$month_input_valid" \
        --argjson courses "$normalized_json" '
        {
            requested_month: $requested_month,
            resolved_month: $resolved_month,
            month_input_valid: $month_input_valid,
            notice: $notice,
            courses: $courses
        }
    '
}

main "$@"
