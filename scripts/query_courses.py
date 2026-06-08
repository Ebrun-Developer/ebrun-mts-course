#!/usr/bin/env python3
"""
ma-tishe-course - 查询马蹄社近期课程和月份课程表

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
import sys
from datetime import datetime
from pathlib import Path
from typing import Any, Dict, List

RECENT_FILE = Path(__file__).resolve().parent.parent / "references" / "recent-courses.json"
CALENDAR_FILE = Path(__file__).resolve().parent.parent / "references" / "course-calendar.json"
MAX_RECENT_RESULTS = 20
VALID_STATUS_ORDER = ["报名中", "已结束"]
MONTH_RE = re.compile(r"^\d{4}-\d{2}$")


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


def normalize_course(item: Any) -> Dict[str, str]:
    if not isinstance(item, dict):
        raise CourseQueryError("数据格式异常: 课程项必须是对象", 7)

    return {
        "title": normalize_text(item.get("title")),
        "url": normalize_text(item.get("url")),
        "status": normalize_text(item.get("status")),
        "date_text": normalize_text(item.get("date_text")),
        "city": normalize_text(item.get("city")),
        "summary": normalize_text(item.get("summary")),
        "month": normalize_text(item.get("month")),
        "tags": ",".join(item.get("tags", [])) if isinstance(item.get("tags"), list) else normalize_text(item.get("tags")),
    }


def load_courses(path: Path) -> List[Dict[str, str]]:
    data = read_json(path)
    courses = data.get("courses", [])
    if not isinstance(courses, list):
        raise CourseQueryError(f"数据格式异常: {path.name} 中 courses 必须是数组", 7)
    return [normalize_course(item) for item in courses]


def get_recent_courses() -> List[Dict[str, str]]:
    courses = load_courses(RECENT_FILE)
    grouped: Dict[str, List[Dict[str, str]]] = {status: [] for status in VALID_STATUS_ORDER}
    fallback: List[Dict[str, str]] = []

    for course in courses:
        status = course.get("status", "")
        if status in grouped:
            grouped[status].append(course)
        else:
            fallback.append(course)

    result: List[Dict[str, str]] = []
    for status in VALID_STATUS_ORDER:
        for course in grouped[status]:
            if len(result) >= MAX_RECENT_RESULTS:
                return result
            result.append(course)

    for course in fallback:
        if len(result) >= MAX_RECENT_RESULTS:
            break
        result.append(course)

    return result


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


def validate_month(month: str) -> str:
    normalized = normalize_text(month)
    if not MONTH_RE.fullmatch(normalized):
        raise CourseQueryError("参数错误: --month 必须为 YYYY-MM 格式，例如 2026-06", 2)
    return normalized


def get_month_courses(month: str) -> List[Dict[str, str]]:
    courses = load_courses(CALENDAR_FILE)
    return [course for course in courses if course.get("month") == month]


def print_json(data: List[Dict[str, str]]) -> None:
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
    parser = argparse.ArgumentParser(description="查询马蹄社课程本地 JSON 数据")
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
                month = validate_month(args.month)
            else:
                month = resolve_relative_month(normalize_text(args.relative), datetime.now())

            courses = get_month_courses(month)
            if args.table:
                print_table(f"马蹄社课程表 {month}", courses)
            else:
                print_json(courses)
            return

        raise CourseQueryError(f"不支持的命令: {args.command}", 2)
    except CourseQueryError as error:
        print(f"[ERROR] {error}", file=sys.stderr)
        sys.exit(error.exit_code)


if __name__ == "__main__":
    main()
