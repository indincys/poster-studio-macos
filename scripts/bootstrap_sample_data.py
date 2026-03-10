from __future__ import annotations

from pathlib import Path

import schema as s
from simple_xlsx import table_to_rows, write_workbook


BASE_DIR = Path(__file__).resolve().parents[1]
DATA_DIR = BASE_DIR / "data"


def build_video_records() -> list[dict[str, str]]:
    return [
        {
            s.VIDEO_FILE_NAME: "thermos_commute_01.mp4",
            s.VIDEO_PATH: "/Users/indincys/Videos/demo/thermos_commute_01.mp4",
            s.COVER_PATH: "/Users/indincys/Pictures/demo/thermos_commute_01.jpg",
            s.SKU_CODE: "SKU-THERMOS-001",
            s.SKU_STYLE: "晨雾白保温杯",
            s.USE_STATUS: "待发布",
            s.PUBLISH_DATE: "2026-03-11",
            s.PUBLISH_TIME: "09:30",
            s.YELLOW_CART_TITLE: "316不锈钢保温杯",
            s.BLUE_SEARCH_TERM: "保温杯",
            s.LOCATION_WECHAT: "上海",
            s.POPULAR_FLAG: "是",
        },
        {
            s.VIDEO_FILE_NAME: "thermos_office_02.mp4",
            s.VIDEO_PATH: "/Users/indincys/Videos/demo/thermos_office_02.mp4",
            s.COVER_PATH: "/Users/indincys/Pictures/demo/thermos_office_02.jpg",
            s.SKU_CODE: "SKU-THERMOS-001",
            s.SKU_STYLE: "晨雾白保温杯",
            s.USE_STATUS: "待发布",
            s.PUBLISH_DATE: "2026-03-11",
            s.PUBLISH_TIME: "12:00",
            s.YELLOW_CART_TITLE: "通勤保温杯",
            s.BLUE_SEARCH_TERM: "通勤杯",
            s.LOCATION_WECHAT: "上海",
            s.POPULAR_FLAG: "否",
        },
        {
            s.VIDEO_FILE_NAME: "eyemask_break_01.mp4",
            s.VIDEO_PATH: "/Users/indincys/Videos/demo/eyemask_break_01.mp4",
            s.COVER_PATH: "/Users/indincys/Pictures/demo/eyemask_break_01.jpg",
            s.SKU_CODE: "SKU-EYEMASK-002",
            s.SKU_STYLE: "薰衣草蒸汽眼罩",
            s.USE_STATUS: "待发布",
            s.PUBLISH_DATE: "2026-03-11",
            s.PUBLISH_TIME: "15:00",
            s.YELLOW_CART_TITLE: "蒸汽眼罩",
            s.BLUE_SEARCH_TERM: "护眼",
            s.LOCATION_WECHAT: "杭州",
            s.POPULAR_FLAG: "是",
        },
        {
            s.VIDEO_FILE_NAME: "eyemask_sleep_02.mp4",
            s.VIDEO_PATH: "/Users/indincys/Videos/demo/eyemask_sleep_02.mp4",
            s.COVER_PATH: "/Users/indincys/Pictures/demo/eyemask_sleep_02.jpg",
            s.SKU_CODE: "SKU-EYEMASK-002",
            s.SKU_STYLE: "薰衣草蒸汽眼罩",
            s.USE_STATUS: "待发布",
            s.PUBLISH_DATE: "2026-03-11",
            s.PUBLISH_TIME: "20:30",
            s.YELLOW_CART_TITLE: "睡前蒸汽眼罩",
            s.BLUE_SEARCH_TERM: "睡前放松",
            s.LOCATION_WECHAT: "杭州",
            s.POPULAR_FLAG: "否",
        },
        {
            s.VIDEO_FILE_NAME: "fan_outdoor_01.mp4",
            s.VIDEO_PATH: "/Users/indincys/Videos/demo/fan_outdoor_01.mp4",
            s.COVER_PATH: "/Users/indincys/Pictures/demo/fan_outdoor_01.jpg",
            s.SKU_CODE: "SKU-FAN-003",
            s.SKU_STYLE: "折叠便携小风扇",
            s.USE_STATUS: "暂停",
            s.PUBLISH_DATE: "2026-03-11",
            s.PUBLISH_TIME: "10:00",
            s.YELLOW_CART_TITLE: "折叠小风扇",
            s.BLUE_SEARCH_TERM: "便携风扇",
            s.LOCATION_WECHAT: "深圳",
            s.POPULAR_FLAG: "否",
        },
    ]


def build_tag_records() -> list[dict[str, str]]:
    return [
        {
            s.SKU_CODE: "SKU-THERMOS-001",
            s.SKU_STYLE_NAME: "晨雾白保温杯",
            s.TAG_1: "#保温杯",
            s.TAG_2: "#通勤好物",
            s.TAG_3: "#办公室好物",
            s.TAG_4: "#上班族必备",
            s.TAG_5: "#实用好物",
        },
        {
            s.SKU_CODE: "SKU-EYEMASK-002",
            s.SKU_STYLE_NAME: "薰衣草蒸汽眼罩",
            s.TAG_1: "#蒸汽眼罩",
            s.TAG_2: "#睡前放松",
            s.TAG_3: "#护眼好物",
            s.TAG_4: "#午休好物",
            s.TAG_5: "#熬夜党",
        },
        {
            s.SKU_CODE: "SKU-FAN-003",
            s.SKU_STYLE_NAME: "折叠便携小风扇",
            s.TAG_1: "#便携风扇",
            s.TAG_2: "#夏季好物",
            s.TAG_3: "#宿舍神器",
            s.TAG_4: "#出门搭子",
            s.TAG_5: "",
        },
    ]


def main() -> None:
    DATA_DIR.mkdir(parents=True, exist_ok=True)

    video_library_path = DATA_DIR / "video_library.xlsx"
    tag_library_path = DATA_DIR / "tag_library.xlsx"

    write_workbook(
        video_library_path,
        {s.VIDEO_SHEET: table_to_rows(s.VIDEO_LIBRARY_HEADERS, build_video_records())},
    )
    write_workbook(
        tag_library_path,
        {s.TAG_SHEET: table_to_rows(s.TAG_LIBRARY_HEADERS, build_tag_records())},
    )

    print(f"Created {video_library_path}")
    print(f"Created {tag_library_path}")


if __name__ == "__main__":
    main()
