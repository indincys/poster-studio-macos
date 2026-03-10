from __future__ import annotations

import argparse
import json
from collections import defaultdict
from pathlib import Path

import schema as s
from simple_xlsx import read_sheet_dicts, table_to_rows, write_workbook


BASE_DIR = Path(__file__).resolve().parents[1]
DEFAULT_VIDEO_LIBRARY = BASE_DIR / "data" / "video_library.xlsx"
DEFAULT_TAG_LIBRARY = BASE_DIR / "data" / "tag_library.xlsx"
DEFAULT_TITLE_LIBRARY = BASE_DIR / "data" / "title_library.xlsx"
DEFAULT_OPTIONS = BASE_DIR / "config" / "task_generation_options.json"
DEFAULT_OUTPUT_DIR = BASE_DIR / "output"


def resolve_path(raw_path: str) -> Path:
    path = Path(raw_path)
    if path.is_absolute():
        return path
    return BASE_DIR / path


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Generate task sheet from video/tag/title libraries.")
    parser.add_argument("--video-library", default=str(DEFAULT_VIDEO_LIBRARY), help="Path to video_library.xlsx")
    parser.add_argument("--tag-library", default=str(DEFAULT_TAG_LIBRARY), help="Path to tag_library.xlsx")
    parser.add_argument("--title-library", default=str(DEFAULT_TITLE_LIBRARY), help="Path to title_library.xlsx")
    parser.add_argument("--options", default=str(DEFAULT_OPTIONS), help="Path to task_generation_options.json")
    parser.add_argument("--output", default="", help="Optional output task sheet path")
    return parser.parse_args()


def load_options(path: Path) -> dict[str, object]:
    return json.loads(path.read_text(encoding="utf-8"))


def to_int(value: str | int | float) -> int:
    try:
        return int(value)
    except (TypeError, ValueError):
        return 0


def normalize_yes_no(value: str) -> str:
    return "是" if value.strip() in {"是", "yes", "true", "1", "hot"} else "否"


def build_tag_map(tag_rows: list[dict[str, str]]) -> dict[str, dict[str, str]]:
    return {row.get(s.SKU_CODE, ""): row for row in tag_rows if row.get(s.SKU_CODE, "")}


def video_matches(video: dict[str, str], options: dict[str, object]) -> bool:
    target_date = str(options.get("target_date", "")).strip()
    if target_date and video.get(s.PUBLISH_DATE, "") != target_date:
        return False

    video_filter = options.get("video_filter", {})
    allowed_status = set(video_filter.get("allowed_status", ["待发布"]))
    if allowed_status and video.get(s.USE_STATUS, "") not in allowed_status:
        return False

    hot_filter = str(video_filter.get("popular_filter", "all"))
    is_hot = normalize_yes_no(video.get(s.POPULAR_FLAG, "")) == "是"
    if hot_filter == "hot" and not is_hot:
        return False
    if hot_filter == "normal" and is_hot:
        return False
    return True


def filter_titles(title_rows: list[dict[str, str]], options: dict[str, object]) -> list[dict[str, str]]:
    title_filter = options.get("title_filter", {})
    allowed_status = set(title_filter.get("allowed_status", ["可用"]))
    mode = str(title_filter.get("mode", "all"))
    threshold = int(title_filter.get("score_threshold", s.TITLE_SCORE_THRESHOLD_DEFAULT))

    rows: list[dict[str, str]] = []
    for row in title_rows:
        if allowed_status and row.get(s.USE_STATUS, "") not in allowed_status:
            continue

        score = to_int(row.get(s.HOT_SCORE, "0"))
        if mode == "high_score" and score < threshold:
            continue
        if mode == "normal_score" and score >= threshold:
            continue
        rows.append(row)

    if rows:
        return rows
    return [row for row in title_rows if row.get(s.USE_STATUS, "") in allowed_status] or title_rows


def choose_title(title_rows: list[dict[str, str]]) -> dict[str, str]:
    ordered = sorted(
        title_rows,
        key=lambda row: (
            to_int(row.get(s.USE_COUNT, "0")),
            -to_int(row.get(s.HOT_SCORE, "0")),
            row.get(s.TITLE, ""),
        ),
    )
    return ordered[0] if ordered else {}


def write_back_title_library(path: Path, title_rows: list[dict[str, str]]) -> None:
    average_score = 0
    if title_rows:
        average_score = round(sum(to_int(row.get(s.HOT_SCORE, "0")) for row in title_rows) / len(title_rows), 1)

    summary_rows = [
        [s.SUMMARY_KEY, s.SUMMARY_VALUE],
        ["标题数量", str(len(title_rows))],
        ["平均爆款分", str(average_score)],
    ]
    write_workbook(
        path,
        {
            s.TITLE_SHEET: table_to_rows(s.TITLE_LIBRARY_HEADERS, title_rows),
            s.SUMMARY_SHEET: summary_rows,
        },
    )


def write_back_video_library(path: Path, video_rows: list[dict[str, str]]) -> None:
    write_workbook(
        path,
        {
            s.VIDEO_SHEET: table_to_rows(s.VIDEO_LIBRARY_HEADERS, video_rows),
        },
    )


def build_task_rows(
    video_rows: list[dict[str, str]],
    tag_map: dict[str, dict[str, str]],
    title_rows: list[dict[str, str]],
    options: dict[str, object],
) -> list[dict[str, str]]:
    platform_plan = options.get("platform_plan", [])
    write_back = options.get("write_back", {})
    task_rows: list[dict[str, str]] = []
    sequence = 1

    filtered_titles = filter_titles(title_rows, options)

    for video in video_rows:
        if not video_matches(video, options):
            continue

        tag_row = tag_map.get(video.get(s.SKU_CODE, ""), {})
        for plan in platform_plan:
            title_row = choose_title(filtered_titles)
            if title_row:
                title_row[s.USE_COUNT] = str(to_int(title_row.get(s.USE_COUNT, "0")) + 1)

            platform = str(plan.get("platform", "")).strip()
            account_name = str(plan.get("account_name", "")).strip()
            mark_original = str(plan.get("mark_original", "是")).strip() or "是"

            task_rows.append(
                {
                    s.TASK_ID: f"TASK-{sequence:04d}",
                    s.TASK_DATE: video.get(s.PUBLISH_DATE, ""),
                    s.SCHEDULED_TIME: video.get(s.PUBLISH_TIME, ""),
                    s.PUBLISH_PLATFORM: platform,
                    s.ACCOUNT_NAME: account_name,
                    s.SKU_STYLE_NAME: video.get(s.SKU_STYLE, ""),
                    s.SKU_CODE: video.get(s.SKU_CODE, ""),
                    s.PRODUCT_NAME: video.get(s.SKU_STYLE, ""),
                    s.VIDEO_FILE_NAME: video.get(s.VIDEO_FILE_NAME, ""),
                    s.VIDEO_PATH: video.get(s.VIDEO_PATH, ""),
                    s.COVER_PATH: video.get(s.COVER_PATH, ""),
                    s.TITLE: title_row.get(s.TITLE, ""),
                    s.TAG_1: tag_row.get(s.TAG_1, ""),
                    s.TAG_2: tag_row.get(s.TAG_2, ""),
                    s.TAG_3: tag_row.get(s.TAG_3, ""),
                    s.TAG_4: tag_row.get(s.TAG_4, ""),
                    s.TAG_5: tag_row.get(s.TAG_5, ""),
                    s.MARK_ORIGINAL: mark_original,
                    s.YELLOW_CART_TITLE_DOUYIN: video.get(s.YELLOW_CART_TITLE, "") if platform == "douyin" else "",
                    s.LOCATION: video.get(s.LOCATION_WECHAT, "") if platform == "shipinhao" else "",
                    s.TASK_STATUS: "待执行",
                }
            )
            sequence += 1

        if write_back.get("update_video_status", True):
            video[s.USE_STATUS] = "已生成任务"

    return task_rows


def build_summary_rows(task_rows: list[dict[str, str]], options: dict[str, object]) -> list[list[str]]:
    counts: dict[str, int] = defaultdict(int)
    for row in task_rows:
        counts[row[s.PUBLISH_PLATFORM]] += 1

    rows = [
        [s.SUMMARY_KEY, s.SUMMARY_VALUE],
        ["任务数量", str(len(task_rows))],
        ["任务日期", str(options.get("target_date", ""))],
        ["视频筛选", str(options.get("video_filter", {}))],
        ["标题筛选", str(options.get("title_filter", {}))],
    ]
    for platform in sorted(counts):
        rows.append([f"{platform}_任务数", str(counts[platform])])
    return rows


def main() -> None:
    args = parse_args()
    video_library_path = resolve_path(args.video_library)
    tag_library_path = resolve_path(args.tag_library)
    title_library_path = resolve_path(args.title_library)
    options_path = resolve_path(args.options)
    options = load_options(options_path)

    target_date = str(options.get("target_date", "")).strip()
    output_path = resolve_path(args.output) if args.output else DEFAULT_OUTPUT_DIR / f"tasks_{target_date}.xlsx"

    video_rows = read_sheet_dicts(video_library_path, sheet_name=s.VIDEO_SHEET)
    tag_rows = read_sheet_dicts(tag_library_path, sheet_name=s.TAG_SHEET)
    title_rows = read_sheet_dicts(title_library_path, sheet_name=s.TITLE_SHEET)

    task_rows = build_task_rows(video_rows, build_tag_map(tag_rows), title_rows, options)

    write_workbook(
        output_path,
        {
            s.TASK_SHEET: table_to_rows(s.TASK_HEADERS, task_rows),
            s.SUMMARY_SHEET: build_summary_rows(task_rows, options),
        },
    )

    write_back = options.get("write_back", {})
    if write_back.get("update_title_use_count", True):
        write_back_title_library(title_library_path, title_rows)
    if write_back.get("update_video_status", True):
        write_back_video_library(video_library_path, video_rows)

    print(f"Created {output_path}")
    print(f"Generated {len(task_rows)} task rows")


if __name__ == "__main__":
    main()
