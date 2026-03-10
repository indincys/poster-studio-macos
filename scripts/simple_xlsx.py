from __future__ import annotations

import re
import zipfile
from datetime import datetime, timezone
from pathlib import Path
from typing import Iterable, Sequence
from xml.etree import ElementTree as ET
from xml.sax.saxutils import escape


MAIN_NS = "http://schemas.openxmlformats.org/spreadsheetml/2006/main"
DOC_PROPS_NS = "http://schemas.openxmlformats.org/officeDocument/2006/extended-properties"
VT_NS = "http://schemas.openxmlformats.org/officeDocument/2006/docPropsVTypes"
REL_NS = "http://schemas.openxmlformats.org/officeDocument/2006/relationships"
PKG_REL_NS = "http://schemas.openxmlformats.org/package/2006/relationships"
CP_NS = "http://schemas.openxmlformats.org/package/2006/metadata/core-properties"
DC_NS = "http://purl.org/dc/elements/1.1/"
DCTERMS_NS = "http://purl.org/dc/terms/"
XSI_NS = "http://www.w3.org/2001/XMLSchema-instance"

NS = {"main": MAIN_NS, "rel": REL_NS}
CELL_REF_RE = re.compile(r"([A-Z]+)([0-9]+)")


def _column_letters(index: int) -> str:
    letters: list[str] = []
    current = index
    while current > 0:
        current, remainder = divmod(current - 1, 26)
        letters.append(chr(65 + remainder))
    return "".join(reversed(letters))


def _column_index(letters: str) -> int:
    result = 0
    for char in letters:
        result = result * 26 + (ord(char) - 64)
    return result


def _cell_reference_to_index(cell_reference: str) -> int:
    match = CELL_REF_RE.fullmatch(cell_reference)
    if not match:
        raise ValueError(f"Unsupported cell reference: {cell_reference}")
    return _column_index(match.group(1))


def _xml_text(value: object) -> str:
    text = "" if value is None else str(value)
    return escape(text)


def _sheet_dimension(max_row: int, max_col: int) -> str:
    if max_row == 0 or max_col == 0:
        return "A1"
    return f"A1:{_column_letters(max_col)}{max_row}"


def _build_sheet_xml(rows: Sequence[Sequence[object]]) -> str:
    max_col = max((len(row) for row in rows), default=0)
    parts = [
        '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>',
        f'<worksheet xmlns="{MAIN_NS}">',
        f'<dimension ref="{_sheet_dimension(len(rows), max_col)}"/>',
        "<sheetData>",
    ]

    for row_index, row in enumerate(rows, start=1):
        parts.append(f'<row r="{row_index}">')
        for col_index, value in enumerate(row, start=1):
            if value is None or value == "":
                continue
            cell_ref = f"{_column_letters(col_index)}{row_index}"
            text = _xml_text(value)
            parts.append(
                f'<c r="{cell_ref}" s="1" t="inlineStr"><is><t xml:space="preserve">{text}</t></is></c>'
            )
        parts.append("</row>")

    parts.append("</sheetData></worksheet>")
    return "".join(parts)


def _workbook_xml(sheet_names: Sequence[str]) -> str:
    sheets_xml = "".join(
        f'<sheet name="{escape(sheet_name)}" sheetId="{index}" r:id="rId{index}"/>'
        for index, sheet_name in enumerate(sheet_names, start=1)
    )
    return (
        '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        f'<workbook xmlns="{MAIN_NS}" xmlns:r="{REL_NS}">'
        f"<sheets>{sheets_xml}</sheets>"
        "</workbook>"
    )


def _content_types_xml(sheet_count: int) -> str:
    sheet_overrides = "".join(
        (
            f'<Override PartName="/xl/worksheets/sheet{index}.xml" '
            'ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>'
        )
        for index in range(1, sheet_count + 1)
    )
    return (
        '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">'
        '<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>'
        '<Default Extension="xml" ContentType="application/xml"/>'
        '<Override PartName="/xl/workbook.xml" '
        'ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>'
        '<Override PartName="/xl/styles.xml" '
        'ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/>'
        '<Override PartName="/docProps/core.xml" '
        'ContentType="application/vnd.openxmlformats-package.core-properties+xml"/>'
        '<Override PartName="/docProps/app.xml" '
        'ContentType="application/vnd.openxmlformats-officedocument.extended-properties+xml"/>'
        f"{sheet_overrides}"
        "</Types>"
    )


def _root_rels_xml() -> str:
    return (
        '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        f'<Relationships xmlns="{PKG_REL_NS}">'
        '<Relationship Id="rId1" '
        'Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" '
        'Target="xl/workbook.xml"/>'
        '<Relationship Id="rId2" '
        'Type="http://schemas.openxmlformats.org/package/2006/relationships/metadata/core-properties" '
        'Target="docProps/core.xml"/>'
        '<Relationship Id="rId3" '
        'Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/extended-properties" '
        'Target="docProps/app.xml"/>'
        "</Relationships>"
    )


def _workbook_rels_xml(sheet_count: int) -> str:
    sheet_rels = "".join(
        (
            f'<Relationship Id="rId{index}" '
            'Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" '
            f'Target="worksheets/sheet{index}.xml"/>'
        )
        for index in range(1, sheet_count + 1)
    )
    style_rel_id = sheet_count + 1
    return (
        '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        f'<Relationships xmlns="{PKG_REL_NS}">'
        f"{sheet_rels}"
        f'<Relationship Id="rId{style_rel_id}" '
        'Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" '
        'Target="styles.xml"/>'
        "</Relationships>"
    )


def _styles_xml() -> str:
    return (
        '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        f'<styleSheet xmlns="{MAIN_NS}">'
        '<fonts count="1"><font><sz val="11"/><name val="Calibri"/><family val="2"/></font></fonts>'
        '<fills count="2">'
        '<fill><patternFill patternType="none"/></fill>'
        '<fill><patternFill patternType="gray125"/></fill>'
        "</fills>"
        '<borders count="1"><border><left/><right/><top/><bottom/><diagonal/></border></borders>'
        '<cellStyleXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" borderId="0"/></cellStyleXfs>'
        '<cellXfs count="2">'
        '<xf numFmtId="0" fontId="0" fillId="0" borderId="0" xfId="0"/>'
        '<xf numFmtId="49" fontId="0" fillId="0" borderId="0" xfId="0" applyNumberFormat="1"/>'
        "</cellXfs>"
        '<cellStyles count="1"><cellStyle name="Normal" xfId="0" builtinId="0"/></cellStyles>'
        "</styleSheet>"
    )


def _app_xml(sheet_names: Sequence[str]) -> str:
    titles = "".join(f"<vt:lpstr>{escape(name)}</vt:lpstr>" for name in sheet_names)
    part_count = len(sheet_names) + 2
    return (
        '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        f'<Properties xmlns="{DOC_PROPS_NS}" xmlns:vt="{VT_NS}">'
        "<Application>Codex</Application>"
        "<DocSecurity>0</DocSecurity>"
        "<ScaleCrop>false</ScaleCrop>"
        "<HeadingPairs><vt:vector size=\"2\" baseType=\"variant\">"
        "<vt:variant><vt:lpstr>Worksheets</vt:lpstr></vt:variant>"
        f"<vt:variant><vt:i4>{len(sheet_names)}</vt:i4></vt:variant>"
        "</vt:vector></HeadingPairs>"
        f'<TitlesOfParts><vt:vector size="{len(sheet_names)}" baseType="lpstr">{titles}</vt:vector></TitlesOfParts>'
        "<Company></Company>"
        "<LinksUpToDate>false</LinksUpToDate>"
        "<SharedDoc>false</SharedDoc>"
        "<HyperlinksChanged>false</HyperlinksChanged>"
        "<AppVersion>16.0300</AppVersion>"
        f"<Parts>{part_count}</Parts>"
        "</Properties>"
    )


def _core_xml() -> str:
    timestamp = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
    return (
        '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        f'<cp:coreProperties xmlns:cp="{CP_NS}" xmlns:dc="{DC_NS}" '
        f'xmlns:dcterms="{DCTERMS_NS}" xmlns:xsi="{XSI_NS}">'
        "<dc:creator>Codex</dc:creator>"
        "<cp:lastModifiedBy>Codex</cp:lastModifiedBy>"
        f'<dcterms:created xsi:type="dcterms:W3CDTF">{timestamp}</dcterms:created>'
        f'<dcterms:modified xsi:type="dcterms:W3CDTF">{timestamp}</dcterms:modified>'
        "</cp:coreProperties>"
    )


def write_workbook(path: str | Path, sheets: dict[str, Sequence[Sequence[object]]]) -> Path:
    output_path = Path(path)
    output_path.parent.mkdir(parents=True, exist_ok=True)

    sheet_names = list(sheets.keys())
    with zipfile.ZipFile(output_path, "w", compression=zipfile.ZIP_DEFLATED) as workbook:
        workbook.writestr("[Content_Types].xml", _content_types_xml(len(sheet_names)))
        workbook.writestr("_rels/.rels", _root_rels_xml())
        workbook.writestr("xl/workbook.xml", _workbook_xml(sheet_names))
        workbook.writestr("xl/_rels/workbook.xml.rels", _workbook_rels_xml(len(sheet_names)))
        workbook.writestr("xl/styles.xml", _styles_xml())
        workbook.writestr("docProps/app.xml", _app_xml(sheet_names))
        workbook.writestr("docProps/core.xml", _core_xml())

        for index, sheet_name in enumerate(sheet_names, start=1):
            workbook.writestr(f"xl/worksheets/sheet{index}.xml", _build_sheet_xml(sheets[sheet_name]))

    return output_path


def _read_shared_strings(workbook: zipfile.ZipFile) -> list[str]:
    shared_strings_path = "xl/sharedStrings.xml"
    if shared_strings_path not in workbook.namelist():
        return []

    root = ET.fromstring(workbook.read(shared_strings_path))
    values: list[str] = []
    for item in root.findall("main:si", NS):
        text_fragments = []
        for node in item.iter():
            if node.tag == f"{{{MAIN_NS}}}t" and node.text:
                text_fragments.append(node.text)
        values.append("".join(text_fragments))
    return values


def _read_sheet_map(workbook: zipfile.ZipFile) -> dict[str, str]:
    workbook_root = ET.fromstring(workbook.read("xl/workbook.xml"))
    rels_root = ET.fromstring(workbook.read("xl/_rels/workbook.xml.rels"))
    relationships = {
        rel.attrib["Id"]: rel.attrib["Target"] for rel in rels_root.findall(f"{{{PKG_REL_NS}}}Relationship")
    }

    sheet_map: dict[str, str] = {}
    for sheet in workbook_root.findall("main:sheets/main:sheet", NS):
        sheet_name = sheet.attrib["name"]
        rel_id = sheet.attrib[f"{{{REL_NS}}}id"]
        target = relationships[rel_id]
        if not target.startswith("worksheets/"):
            continue
        sheet_map[sheet_name] = f"xl/{target}"
    return sheet_map


def read_sheet_rows(path: str | Path, sheet_name: str | None = None) -> list[list[str]]:
    workbook_path = Path(path)
    with zipfile.ZipFile(workbook_path, "r") as workbook:
        shared_strings = _read_shared_strings(workbook)
        sheet_map = _read_sheet_map(workbook)
        if not sheet_map:
            return []

        selected_name = sheet_name or next(iter(sheet_map))
        if selected_name not in sheet_map:
            available = ", ".join(sheet_map)
            raise KeyError(f"Sheet '{selected_name}' not found in {workbook_path}. Available: {available}")

        root = ET.fromstring(workbook.read(sheet_map[selected_name]))
        rows: list[list[str]] = []
        for row in root.findall("main:sheetData/main:row", NS):
            values_by_col: dict[int, str] = {}
            max_col = 0
            for cell in row.findall("main:c", NS):
                cell_ref = cell.attrib.get("r")
                if not cell_ref:
                    continue
                col_index = _cell_reference_to_index(cell_ref)
                max_col = max(max_col, col_index)
                cell_type = cell.attrib.get("t")
                value = ""

                if cell_type == "inlineStr":
                    inline = cell.find("main:is", NS)
                    if inline is not None:
                        value = "".join(node.text or "" for node in inline.iter() if node.tag == f"{{{MAIN_NS}}}t")
                else:
                    value_node = cell.find("main:v", NS)
                    raw_value = "" if value_node is None or value_node.text is None else value_node.text
                    if cell_type == "s" and raw_value:
                        value = shared_strings[int(raw_value)]
                    else:
                        value = raw_value

                values_by_col[col_index] = value

            if max_col == 0:
                rows.append([])
                continue

            ordered_row = [""] * max_col
            for col_index, value in values_by_col.items():
                ordered_row[col_index - 1] = value
            rows.append(ordered_row)

    return rows


def read_sheet_dicts(path: str | Path, sheet_name: str | None = None) -> list[dict[str, str]]:
    rows = read_sheet_rows(path, sheet_name=sheet_name)
    if not rows:
        return []

    headers = [header.strip() for header in rows[0]]
    items: list[dict[str, str]] = []
    for row in rows[1:]:
        padded = row + [""] * max(0, len(headers) - len(row))
        record = {header: padded[index].strip() for index, header in enumerate(headers) if header}
        if any(value for value in record.values()):
            items.append(record)
    return items


def table_to_rows(headers: Sequence[str], records: Iterable[dict[str, object]]) -> list[list[object]]:
    rows: list[list[object]] = [list(headers)]
    for record in records:
        rows.append([record.get(header, "") for header in headers])
    return rows
