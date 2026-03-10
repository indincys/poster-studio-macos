from __future__ import annotations

import argparse
import json
import re
import urllib.error
import urllib.request
from pathlib import Path

import schema as s
from simple_xlsx import table_to_rows, write_workbook


BASE_DIR = Path(__file__).resolve().parents[1]
DEFAULT_OUTPUT = BASE_DIR / "data" / "title_library.xlsx"
ALLOWED_SPECIALS = "《》“”：:+?%℃"
HOT_WORDS = ("必备", "别错过", "闭眼入", "回购", "一定要", "实测", "真香", "省心", "推荐")


def resolve_path(raw_path: str) -> Path:
    path = Path(raw_path)
    if path.is_absolute():
        return path
    return BASE_DIR / path


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Generate title library rows with short titles.")
    parser.add_argument("--output", default=str(DEFAULT_OUTPUT), help="Path to title_library.xlsx")
    parser.add_argument("--prompt", default="多平台短视频商品标题，偏种草和转化风格", help="Prompt or topic for title generation")
    parser.add_argument("--count", type=int, default=12, help="How many title rows to generate")
    parser.add_argument("--api-key", default="", help="OpenAI-compatible API key")
    parser.add_argument("--base-url", default="", help="OpenAI-compatible base URL, e.g. https://api.openai.com/v1")
    parser.add_argument("--model", default="", help="OpenAI-compatible model name")
    return parser.parse_args()


def normalize_title(raw_title: str) -> str:
    text = raw_title.strip()
    text = re.sub(r"^[0-9]+[.)、\s-]*", "", text)
    text = re.sub(r"\s+", " ", text)
    return text.strip(" -")


def build_short_title(title: str) -> str:
    text = title.replace("，", " ").replace(",", " ")
    allowed_pattern = rf"[^0-9A-Za-z\u4e00-\u9fff\s{re.escape(ALLOWED_SPECIALS)}]"
    text = re.sub(allowed_pattern, "", text)
    text = re.sub(r"\s+", " ", text).strip()

    if len(text) > 16:
        text = text[:16].rstrip()

    if len(text) >= 6:
        return text

    compact = text.replace(" ", "")
    if len(compact) >= 6:
        return compact[:16]
    return compact[:16]


def estimate_hot_score(title: str, order_index: int) -> int:
    score = 68 + max(0, 12 - order_index)
    score += sum(1 for word in HOT_WORDS if word in title) * 3
    score += min(8, len(title) // 4)
    return max(50, min(99, score))


def fallback_titles(prompt: str, count: int) -> list[str]:
    topic = prompt.strip() or "商品"
    templates = [
        f"{topic}真的越用越顺手",
        f"这条别滑走，{topic}我想认真推荐",
        f"{topic}别乱选，这种更省心",
        f"{topic}用下来最想夸的是这点",
        f"最近反复回购的{topic}",
        f"{topic}实测后，我更愿意留这款",
        f"{topic}做得对不对，看这几个细节",
        f"如果只留一款{topic}，我会选它",
        f"{topic}不一定最贵，但真的更好用",
        f"{topic}为什么容易出单，这条说清楚",
        f"{topic}闭眼入之前，先看这一条",
        f"{topic}适不适合你，看完就知道",
        f"{topic}一上手就知道差别在哪",
        f"{topic}值不值得买，重点看这里",
        f"{topic}这版细节，真的更适合日常用",
    ]

    titles: list[str] = []
    for index in range(count):
        titles.append(templates[index % len(templates)])
    return titles


def parse_ai_payload(raw_text: str) -> list[dict[str, object]]:
    cleaned = raw_text.strip()
    if not cleaned:
        return []

    try:
        payload = json.loads(cleaned)
        if isinstance(payload, list):
            rows: list[dict[str, object]] = []
            for item in payload:
                if isinstance(item, dict) and "title" in item:
                    rows.append(item)
                elif isinstance(item, str):
                    rows.append({"title": item})
            return rows
    except json.JSONDecodeError:
        pass

    rows = []
    for line in cleaned.splitlines():
        title = normalize_title(line)
        if title:
            rows.append({"title": title})
    return rows


def request_ai_titles(prompt: str, count: int, api_key: str, base_url: str, model: str) -> list[dict[str, object]]:
    system_prompt = (
        "你是中文短视频标题策划。请输出 JSON 数组，每个元素包含 title 和可选 hotScore。"
        "标题要适合商品短视频发布，不要加序号。"
    )
    user_prompt = (
        f"请围绕以下主题生成 {count} 条中文标题，并尽量给出 0-100 的爆款分 hotScore：\n"
        f"{prompt}\n"
        "只输出 JSON。"
    )
    payload = {
        "model": model,
        "messages": [
            {"role": "system", "content": system_prompt},
            {"role": "user", "content": user_prompt},
        ],
        "temperature": 0.8,
    }

    request = urllib.request.Request(
        url=f"{base_url.rstrip('/')}/chat/completions",
        data=json.dumps(payload).encode("utf-8"),
        headers={
            "Content-Type": "application/json",
            "Authorization": f"Bearer {api_key}",
        },
        method="POST",
    )

    with urllib.request.urlopen(request, timeout=60) as response:
        body = json.loads(response.read().decode("utf-8"))

    content = body["choices"][0]["message"]["content"]
    return parse_ai_payload(content)


def generate_title_rows(args: argparse.Namespace) -> list[dict[str, object]]:
    if args.api_key and args.base_url and args.model:
        try:
            raw_rows = request_ai_titles(args.prompt, args.count, args.api_key, args.base_url, args.model)
        except (urllib.error.URLError, KeyError, IndexError, TimeoutError) as exc:
            print(f"AI request failed, fallback to local generator: {exc}")
            raw_rows = [{"title": title} for title in fallback_titles(args.prompt, args.count)]
    else:
        raw_rows = [{"title": title} for title in fallback_titles(args.prompt, args.count)]

    title_rows: list[dict[str, object]] = []
    seen_titles: set[str] = set()
    for index, item in enumerate(raw_rows, start=1):
        raw_title = normalize_title(str(item.get("title", "")))
        if not raw_title or raw_title in seen_titles:
            continue
        seen_titles.add(raw_title)

        hot_score = item.get("hotScore")
        if isinstance(hot_score, str) and hot_score.isdigit():
            resolved_score = int(hot_score)
        elif isinstance(hot_score, (int, float)):
            resolved_score = int(hot_score)
        else:
            resolved_score = estimate_hot_score(raw_title, index)

        title_rows.append(
            {
                s.TITLE: raw_title,
                s.USE_STATUS: "可用",
                s.USE_COUNT: 0,
                s.HOT_SCORE: max(0, min(100, resolved_score)),
                s.SHORT_TITLE_WECHAT: build_short_title(raw_title),
            }
        )

        if len(title_rows) >= args.count:
            break

    return title_rows


def build_summary_rows(titles: list[dict[str, object]], prompt: str) -> list[list[str]]:
    average_score = 0
    if titles:
        average_score = round(sum(int(row[s.HOT_SCORE]) for row in titles) / len(titles), 1)

    return [
        [s.SUMMARY_KEY, s.SUMMARY_VALUE],
        ["标题数量", str(len(titles))],
        ["平均爆款分", str(average_score)],
        ["生成主题", prompt],
    ]


def main() -> None:
    args = parse_args()
    output_path = resolve_path(args.output)
    titles = generate_title_rows(args)

    write_workbook(
        output_path,
        {
            s.TITLE_SHEET: table_to_rows(s.TITLE_LIBRARY_HEADERS, titles),
            s.SUMMARY_SHEET: build_summary_rows(titles, args.prompt),
        },
    )

    print(f"Created {output_path}")
    print(f"Generated {len(titles)} title rows")


if __name__ == "__main__":
    main()
