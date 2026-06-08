#!/usr/bin/env python3
"""
ebrun-mts-course - 查询马蹄社近期课程和月份课程表

用法:
    python3 query_courses.py recent --json
    python3 query_courses.py recent --table
    python3 query_courses.py month --month 2026-06 --json
    python3 query_courses.py month --relative current --json
    python3 query_courses.py month --relative next --table
"""

import argparse
import json
import re
import socket
import sys
import time
from datetime import datetime
from pathlib import Path
from typing import Any, Dict, List
from urllib import request
from urllib.error import HTTPError, URLError
from urllib.parse import urlparse

CONFIG_FILE = Path(__file__).resolve().parent.parent / "references" / "config.json"
MONTH_RE = re.compile(r"^\d{4}-(0[1-9]|1[0-2])$")
ALLOWED_DOMAINS = ["www.ebrun.com", "api.ebrun.com"]
DEFAULT_TIMEOUT = 10
DEFAULT_RETRIES = 3
RETRYABLE_STATUS_CODES = {429, 500, 502, 503, 504}
HEADERS = {
    "User-Agent": "Mozilla/5.0 (EbrunMtsCourse/1.0)",
    "Accept": "application/json, text/plain, */*",
    "Referer": "https://www.ebrun.com/",
}


class CourseQueryError(Exception):
    def __init__(self, message: str, exit_code: int):
        super().__init__(message)
        self.exit_code = exit_code


def read_json(path: Path) -> Dict[str, Any]:
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except FileNotFoundError as error:
        raise CourseQueryError(f"未找到数据文件: {path}", 5) from error
    except json.JSONDecodeError as error:
        raise CourseQueryError(f"JSON 解析失败: {error}", 7) from error

    if not isinstance(data, dict):
        raise CourseQueryError(f"数据格式异常: {path.name} 顶层必须是对象", 7)
    return data


def normalize_text(value: Any) -> str:
    if value is None:
        return ""
    return " ".join(str(value).replace("\r", " ").replace("\n", " ").split())


def is_safe_url(url: str) -> bool:
    try:
        parsed = urlparse(url)
    except Exception:
        return False

    if parsed.scheme != "https" or not parsed.hostname:
        return False

    return any(
        parsed.hostname == domain or parsed.hostname.endswith("." + domain)
        for domain in ALLOWED_DOMAINS
    )


def validate_url(url: str, label: str) -> str:
    normalized = normalize_text(url)
    if not normalized:
        raise CourseQueryError(f"配置错误: {label} 不能为空", 7)
    if not is_safe_url(normalized):
        raise CourseQueryError(f"安全性风险: 非授权地址 -> {normalized}", 3)
    return normalized


def read_config() -> Dict[str, Any]:
    config = read_json(CONFIG_FILE)
    data_source = config.get("data_source")
    if not isinstance(data_source, dict):
        raise CourseQueryError("配置错误: data_source 必须是对象", 7)
    return config


def get_data_source_url(query_type: str) -> str:
    config = read_config()
    data_source = config["data_source"]

    if query_type == "recent":
        return validate_url(
            data_source.get("recent_real_api_url", ""),
            "data_source.recent_real_api_url",
        )

    if query_type == "month":
        return validate_url(
            data_source.get("monthly_real_api_url", ""),
            "data_source.monthly_real_api_url",
        )

    raise CourseQueryError(f"不支持的查询类型: {query_type}", 2)


def should_retry_http(status_code: int) -> bool:
    return status_code in RETRYABLE_STATUS_CODES


def should_retry_network(error: BaseException) -> bool:
    if isinstance(error, (TimeoutError, socket.timeout)):
        return True
    if isinstance(error, URLError):
        reason = getattr(error, "reason", None)
        return isinstance(reason, (TimeoutError, socket.timeout))
    return False


def fetch_json(url: str, timeout: int = DEFAULT_TIMEOUT, retries: int = DEFAULT_RETRIES) -> Any:
    last_error: CourseQueryError | None = None

    for attempt in range(1, retries + 1):
        try:
            req = request.Request(url, headers=HEADERS)
            with request.urlopen(req, timeout=timeout) as response:
                return json.loads(response.read().decode("utf-8"))
        except HTTPError as error:
            if error.code == 403:
                last_error = CourseQueryError("请求被拒绝: HTTP 403", 6)
            elif error.code == 404:
                last_error = CourseQueryError("资源不存在: HTTP 404", 5)
            elif error.code == 503:
                last_error = CourseQueryError("服务暂时不可用: HTTP 503，可稍后重试", 4)
            else:
                last_error = CourseQueryError(f"请求失败: HTTP {error.code}", 4)

            if not should_retry_http(error.code) or attempt >= retries:
                raise last_error
        except json.JSONDecodeError as error:
            raise CourseQueryError(f"JSON 解析失败: {error}", 7) from error
        except (URLError, TimeoutError, socket.timeout) as error:
            reason = getattr(error, "reason", error)
            if should_retry_network(error):
                last_error = CourseQueryError("网络请求超时，请稍后重试", 4)
            else:
                last_error = CourseQueryError(f"网络请求失败: {reason}", 4)

            if not should_retry_network(error) or attempt >= retries:
                raise last_error
        except Exception as error:
            raise CourseQueryError(f"获取数据异常: {error}", 4) from error

        time.sleep(min(attempt, 2))

    if last_error is not None:
        raise last_error
    raise CourseQueryError("获取数据失败: 未知错误", 4)


def normalize_course(item: Any, month: str = "") -> Dict[str, str]:
    if not isinstance(item, dict):
        raise CourseQueryError("数据格式异常: 课程项必须是对象", 7)

    return {
        "title": normalize_text(item.get("title")) or "未注明",
        "url": normalize_text(item.get("url")),
        "status": normalize_text(item.get("status")) or "状态待更新",
        "date_text": normalize_text(item.get("date_text") or item.get("date")) or "未注明",
        "city": normalize_text(item.get("city")) or "未注明",
        "summary": normalize_text(item.get("summary")) or "未注明",
        "month": month,
        "tags": ",".join(item.get("tags", []))
        if isinstance(item.get("tags"), list)
        else normalize_text(item.get("tags")),
    }


def get_recent_courses() -> List[Dict[str, str]]:
    data = fetch_json(get_data_source_url("recent"))
    if not isinstance(data, list):
        raise CourseQueryError("接口返回格式异常: 近期课程顶层必须是数组", 7)

    return [normalize_course(item) for item in data]


def resolve_relative_month(relative: str, now: datetime) -> str:
    base_year = now.year
    base_month = now.month

    if relative == "current":
        return f"{base_year:04d}-{base_month:02d}"

    if relative != "next":
        raise CourseQueryError("参数错误: --relative 只支持 current 或 next", 2)

    if base_month == 12:
        return f"{base_year + 1:04d}-01"
    return f"{base_year:04d}-{base_month + 1:02d}"


def current_month(now: datetime) -> str:
    return f"{now.year:04d}-{now.month:02d}"


def validate_month(month: str) -> str:
    normalized = normalize_text(month)
    if not MONTH_RE.fullmatch(normalized):
        raise CourseQueryError("参数错误: --month 必须为 YYYY-MM 格式，例如 2026-06", 2)
    return normalized


def resolve_month_input(month: str, now: datetime) -> Dict[str, str | bool]:
    normalized = normalize_text(month)
    fallback_month = current_month(now)

    if MONTH_RE.fullmatch(normalized):
        return {
            "requested_month": normalized,
            "resolved_month": normalized,
            "month_input_valid": True,
            "notice": "",
        }

    return {
        "requested_month": normalized or month,
        "resolved_month": fallback_month,
        "month_input_valid": False,
        "notice": f"你提供的月份不正确，已为你展示当前月份（{fallback_month}）课程。",
    }


def to_month_label(month: str) -> str:
    return f"{int(month.split('-')[1])}月"


def get_month_courses(month: str) -> List[Dict[str, str]]:
    data = fetch_json(get_data_source_url("month"))
    if not isinstance(data, dict):
        raise CourseQueryError("接口返回格式异常: 月份课程表顶层必须是对象", 7)

    month_label = to_month_label(month)
    month_courses = data.get(month_label, [])
    if month_courses is None:
        return []
    if not isinstance(month_courses, list):
        raise CourseQueryError(f"接口返回格式异常: {month_label} 对应数据必须是数组", 7)

    return [normalize_course(item, month=month) for item in month_courses]


def print_json(data: Any) -> None:
    print(json.dumps(data, ensure_ascii=False, indent=2))


def print_table(title: str, data: List[Dict[str, str]]) -> None:
    if not data:
        print("暂无课程数据")
        return

    width = 72
    print(f"\n┌{'─' * (width - 2)}┐")
    print(f"│  {title:<66}│")
    print(f"├{'─' * (width - 2)}┤")

    for index, course in enumerate(data, start=1):
        line_title = course.get("title") or "无标题"
        line_status = course.get("status") or "未知状态"
        line_date = course.get("date_text") or "未知时间"
        line_city = course.get("city") or "未知地点"
        print(f"│  {index:2d}. {line_title[:60]:<60} │")
        print(f"│      状态: {line_status[:12]:<12} 时间: {line_date[:20]:<20}│")
        print(f"│      地点: {line_city[:52]:<52} │")
        if index < len(data):
            print(f"├{'─' * (width - 2)}┤")

    print(f"└{'─' * (width - 2)}┘")
    print(f"\n共 {len(data)} 条课程")


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="查询马蹄社课程真实接口数据")
    subparsers = parser.add_subparsers(dest="command", required=True)

    recent_parser = subparsers.add_parser("recent", help="查询最近课程")
    recent_output = recent_parser.add_mutually_exclusive_group()
    recent_output.add_argument("--json", action="store_true", help="输出 JSON")
    recent_output.add_argument("--table", action="store_true", help="输出 ASCII 表格")

    month_parser = subparsers.add_parser("month", help="按月份查询课程表")
    month_group = month_parser.add_mutually_exclusive_group(required=True)
    month_group.add_argument("--month", help="指定月份，格式 YYYY-MM")
    month_group.add_argument("--relative", help="相对月份，支持 current 或 next")
    month_output = month_parser.add_mutually_exclusive_group()
    month_output.add_argument("--json", action="store_true", help="输出 JSON")
    month_output.add_argument("--table", action="store_true", help="输出 ASCII 表格")

    return parser


def main() -> None:
    parser = build_parser()
    args = parser.parse_args()

    try:
        if args.command == "recent":
            courses = get_recent_courses()
            if args.table:
                print_table("马蹄社近期课程", courses)
            else:
                print_json(courses)
            return

        if args.command == "month":
            if args.month:
                month_result = resolve_month_input(args.month, datetime.now())
            else:
                resolved_month = resolve_relative_month(normalize_text(args.relative), datetime.now())
                month_result = {
                    "requested_month": resolved_month,
                    "resolved_month": resolved_month,
                    "month_input_valid": True,
                    "notice": "",
                }

            month = str(month_result["resolved_month"])
            courses = get_month_courses(month)
            if args.table:
                if not month_result["month_input_valid"]:
                    print(str(month_result["notice"]))
                    print("")
                print_table(f"马蹄社课程表 {month}", courses)
            else:
                print_json(
                    {
                        "requested_month": month_result["requested_month"],
                        "resolved_month": month,
                        "month_input_valid": month_result["month_input_valid"],
                        "notice": month_result["notice"],
                        "courses": courses,
                    }
                )
            return

        raise CourseQueryError(f"不支持的命令: {args.command}", 2)
    except CourseQueryError as error:
        print(f"[ERROR] {error}", file=sys.stderr)
        sys.exit(error.exit_code)


if __name__ == "__main__":
    main()
