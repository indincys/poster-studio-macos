import Foundation

enum XlsxError: LocalizedError {
    case sheetNotFound(String)
    case invalidWorkbook
    case processFailed(String)

    var errorDescription: String? {
        switch self {
        case .sheetNotFound(let name):
            return "找不到工作表：\(name)"
        case .invalidWorkbook:
            return "Excel 文件格式无效"
        case .processFailed(let message):
            return message
        }
    }
}

struct WorkbookSheet {
    var name: String
    var rows: [[String]]
}

enum XlsxService {
    static func readRows(from url: URL, sheetName: String) throws -> [[String]] {
        let tempDirectory = try unzipWorkbook(url)
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        let workbookXML = try String(contentsOf: tempDirectory.appendingPathComponent("xl/workbook.xml"), encoding: .utf8)
        let relationshipsXML = try String(contentsOf: tempDirectory.appendingPathComponent("xl/_rels/workbook.xml.rels"), encoding: .utf8)
        let sharedStrings = try readSharedStrings(from: tempDirectory)
        let relationshipTargets = regexMatches(in: relationshipsXML, pattern: #"<Relationship[^>]*Id="([^"]+)"[^>]*Target="([^"]+)"[^>]*/?>"#)
        var targetMap: [String: String] = [:]
        for match in relationshipTargets where match.count >= 3 {
            targetMap[match[1]] = match[2]
        }

        let sheets = regexMatches(in: workbookXML, pattern: #"<sheet[^>]*name="([^"]+)"[^>]*r:id="([^"]+)"[^>]*/?>"#)
        guard let sheetMatch = sheets.first(where: { $0.count >= 3 && $0[1] == sheetName }),
              let target = targetMap[sheetMatch[2]] else {
            throw XlsxError.sheetNotFound(sheetName)
        }

        let sheetXML = try String(contentsOf: tempDirectory.appendingPathComponent("xl").appendingPathComponent(target), encoding: .utf8)
        return parseRows(from: sheetXML, sharedStrings: sharedStrings)
    }

    static func writeWorkbook(to url: URL, sheets: [WorkbookSheet]) throws {
        let fileManager = FileManager.default
        let tempDirectory = try fileManager.url(
            for: .itemReplacementDirectory,
            in: .userDomainMask,
            appropriateFor: url,
            create: true
        )
        defer { try? fileManager.removeItem(at: tempDirectory) }

        try fileManager.createDirectory(at: tempDirectory.appendingPathComponent("_rels"), withIntermediateDirectories: true)
        try fileManager.createDirectory(at: tempDirectory.appendingPathComponent("xl/_rels"), withIntermediateDirectories: true)
        try fileManager.createDirectory(at: tempDirectory.appendingPathComponent("xl/worksheets"), withIntermediateDirectories: true)
        try fileManager.createDirectory(at: tempDirectory.appendingPathComponent("docProps"), withIntermediateDirectories: true)

        try write("[Content_Types].xml", in: tempDirectory, contents: contentTypesXML(sheetCount: sheets.count))
        try write("_rels/.rels", in: tempDirectory, contents: rootRelationshipsXML())
        try write("xl/workbook.xml", in: tempDirectory, contents: workbookXML(sheetNames: sheets.map(\.name)))
        try write("xl/_rels/workbook.xml.rels", in: tempDirectory, contents: workbookRelationshipsXML(sheetCount: sheets.count))
        try write("xl/styles.xml", in: tempDirectory, contents: stylesXML())
        try write("docProps/app.xml", in: tempDirectory, contents: appXML(sheetNames: sheets.map(\.name)))
        try write("docProps/core.xml", in: tempDirectory, contents: coreXML())

        for (index, sheet) in sheets.enumerated() {
            try write("xl/worksheets/sheet\(index + 1).xml", in: tempDirectory, contents: worksheetXML(rows: sheet.rows))
        }

        try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if fileManager.fileExists(atPath: url.path) {
            try fileManager.removeItem(at: url)
        }

        try runProcess(
            executable: "/usr/bin/zip",
            arguments: ["-qr", url.path, "."],
            currentDirectory: tempDirectory
        )
    }

    private static func unzipWorkbook(_ url: URL) throws -> URL {
        let tempDirectory = try FileManager.default.url(
            for: .itemReplacementDirectory,
            in: .userDomainMask,
            appropriateFor: url,
            create: true
        )
        try runProcess(
            executable: "/usr/bin/unzip",
            arguments: ["-qq", "-o", url.path, "-d", tempDirectory.path],
            currentDirectory: nil
        )
        return tempDirectory
    }

    private static func readSharedStrings(from root: URL) throws -> [String] {
        let url = root.appendingPathComponent("xl/sharedStrings.xml")
        guard FileManager.default.fileExists(atPath: url.path) else {
            return []
        }
        let xml = try String(contentsOf: url, encoding: .utf8)
        let items = regexMatches(in: xml, pattern: #"<si[^>]*>(.*?)</si>"#, options: [.dotMatchesLineSeparators])
        return items.compactMap { match in
            guard match.count >= 2 else { return nil }
            return collectText(fromInlineXML: match[1])
        }
    }

    private static func parseRows(from sheetXML: String, sharedStrings: [String]) -> [[String]] {
        let rowMatches = regexMatches(in: sheetXML, pattern: #"<row[^>]*>(.*?)</row>"#, options: [.dotMatchesLineSeparators])
        var rows: [[String]] = []

        for rowMatch in rowMatches {
            guard rowMatch.count >= 2 else { continue }
            let rowXML = rowMatch[1]
            let cellMatches = regexMatches(
                in: rowXML,
                pattern: #"<c[^>]*r="([A-Z]+[0-9]+)"(?:[^>]*t="([^"]+)")?[^>]*>(.*?)</c>"#,
                options: [.dotMatchesLineSeparators]
            )
            var valuesByColumn: [Int: String] = [:]
            var maxColumn = 0

            for cellMatch in cellMatches where cellMatch.count >= 4 {
                let cellReference = cellMatch[1]
                let cellType = cellMatch[2]
                let cellBody = cellMatch[3]
                let column = columnIndex(from: cellReference)
                maxColumn = max(maxColumn, column)

                let value: String
                if cellType == "inlineStr" {
                    value = collectText(fromInlineXML: cellBody)
                } else if cellType == "s" {
                    let sharedIndex = Int(firstCapturedGroup(in: cellBody, pattern: #"<v[^>]*>(.*?)</v>"#) ?? "") ?? -1
                    value = sharedStrings[safe: sharedIndex] ?? ""
                } else {
                    value = decodeXML(firstCapturedGroup(in: cellBody, pattern: #"<v[^>]*>(.*?)</v>"#) ?? "")
                }

                valuesByColumn[column] = value
            }

            var row: [String] = Array(repeating: "", count: maxColumn)
            for (column, value) in valuesByColumn where column > 0 && column - 1 < row.count {
                row[column - 1] = value
            }
            rows.append(row)
        }

        return rows
    }

    private static func collectText(fromInlineXML xml: String) -> String {
        let textMatches = regexMatches(in: xml, pattern: #"<t[^>]*>(.*?)</t>"#, options: [.dotMatchesLineSeparators])
        return textMatches.compactMap { $0.count >= 2 ? decodeXML($0[1]) : nil }.joined()
    }

    private static func firstCapturedGroup(in text: String, pattern: String) -> String? {
        regexMatches(in: text, pattern: pattern, options: [.dotMatchesLineSeparators]).first?[safe: 1]
    }

    private static func regexMatches(in text: String, pattern: String, options: NSRegularExpression.Options = []) -> [[String]] {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: options) else { return [] }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.matches(in: text, options: [], range: range).map { match in
            (0..<match.numberOfRanges).compactMap { index in
                guard let range = Range(match.range(at: index), in: text) else { return nil }
                return String(text[range])
            }
        }
    }

    private static func columnIndex(from reference: String) -> Int {
        let letters = reference.prefix { $0.isLetter }
        var index = 0
        for scalar in letters.unicodeScalars {
            index = index * 26 + Int(scalar.value) - 64
        }
        return index
    }

    private static func columnLetters(for index: Int) -> String {
        var number = index
        var letters: [Character] = []
        while number > 0 {
            let remainder = (number - 1) % 26
            letters.append(Character(UnicodeScalar(65 + remainder)!))
            number = (number - 1) / 26
        }
        return String(letters.reversed())
    }

    private static func worksheetXML(rows: [[String]]) -> String {
        let maxColumn = rows.map(\.count).max() ?? 0
        let dimension = maxColumn == 0 ? "A1" : "A1:\(columnLetters(for: maxColumn))\(rows.count)"
        var parts: [String] = [
            #"<?xml version="1.0" encoding="UTF-8" standalone="yes"?>"#,
            #"<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">"#,
            #"<dimension ref="\#(dimension)"/>"#,
            "<sheetData>",
        ]

        for (rowIndex, row) in rows.enumerated() {
            parts.append(#"<row r="\#(rowIndex + 1)">"#)
            for (columnIndex, value) in row.enumerated() where !value.isEmpty {
                let cellReference = "\(columnLetters(for: columnIndex + 1))\(rowIndex + 1)"
                parts.append(#"<c r="\#(cellReference)" s="1" t="inlineStr"><is><t xml:space="preserve">\#(escapeXML(value))</t></is></c>"#)
            }
            parts.append("</row>")
        }

        parts.append("</sheetData></worksheet>")
        return parts.joined()
    }

    private static func workbookXML(sheetNames: [String]) -> String {
        let sheets = sheetNames.enumerated().map { index, name in
            #"<sheet name="\#(escapeXMLAttribute(name))" sheetId="\#(index + 1)" r:id="rId\#(index + 1)"/>"#
        }.joined()

        return [
            #"<?xml version="1.0" encoding="UTF-8" standalone="yes"?>"#,
            #"<workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"><sheets>"#,
            sheets,
            "</sheets></workbook>",
        ].joined()
    }

    private static func contentTypesXML(sheetCount: Int) -> String {
        let sheetOverrides = (1...sheetCount).map { index in
            #"<Override PartName="/xl/worksheets/sheet\#(index).xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>"#
        }.joined()

        return [
            #"<?xml version="1.0" encoding="UTF-8" standalone="yes"?>"#,
            #"<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">"#,
            #"<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>"#,
            #"<Default Extension="xml" ContentType="application/xml"/>"#,
            #"<Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>"#,
            #"<Override PartName="/xl/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/>"#,
            #"<Override PartName="/docProps/core.xml" ContentType="application/vnd.openxmlformats-package.core-properties+xml"/>"#,
            #"<Override PartName="/docProps/app.xml" ContentType="application/vnd.openxmlformats-officedocument.extended-properties+xml"/>"#,
            sheetOverrides,
            "</Types>",
        ].joined()
    }

    private static func rootRelationshipsXML() -> String {
        [
            #"<?xml version="1.0" encoding="UTF-8" standalone="yes"?>"#,
            #"<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">"#,
            #"<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/>"#,
            #"<Relationship Id="rId2" Type="http://schemas.openxmlformats.org/package/2006/relationships/metadata/core-properties" Target="docProps/core.xml"/>"#,
            #"<Relationship Id="rId3" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/extended-properties" Target="docProps/app.xml"/>"#,
            "</Relationships>",
        ].joined()
    }

    private static func workbookRelationshipsXML(sheetCount: Int) -> String {
        let sheetRelationships = (1...sheetCount).map { index in
            #"<Relationship Id="rId\#(index)" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet\#(index).xml"/>"#
        }.joined()
        let stylesID = sheetCount + 1
        return [
            #"<?xml version="1.0" encoding="UTF-8" standalone="yes"?>"#,
            #"<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">"#,
            sheetRelationships,
            #"<Relationship Id="rId\#(stylesID)" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/>"#,
            "</Relationships>",
        ].joined()
    }

    private static func stylesXML() -> String {
        [
            #"<?xml version="1.0" encoding="UTF-8" standalone="yes"?>"#,
            #"<styleSheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">"#,
            #"<fonts count="1"><font><sz val="11"/><name val="Calibri"/><family val="2"/></font></fonts>"#,
            #"<fills count="2"><fill><patternFill patternType="none"/></fill><fill><patternFill patternType="gray125"/></fill></fills>"#,
            #"<borders count="1"><border><left/><right/><top/><bottom/><diagonal/></border></borders>"#,
            #"<cellStyleXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" borderId="0"/></cellStyleXfs>"#,
            #"<cellXfs count="2"><xf numFmtId="0" fontId="0" fillId="0" borderId="0" xfId="0"/><xf numFmtId="49" fontId="0" fillId="0" borderId="0" xfId="0" applyNumberFormat="1"/></cellXfs>"#,
            #"<cellStyles count="1"><cellStyle name="Normal" xfId="0" builtinId="0"/></cellStyles>"#,
            "</styleSheet>",
        ].joined()
    }

    private static func appXML(sheetNames: [String]) -> String {
        let titles = sheetNames.map { "<vt:lpstr>\(escapeXML($0))</vt:lpstr>" }.joined()
        return [
            #"<?xml version="1.0" encoding="UTF-8" standalone="yes"?>"#,
            #"<Properties xmlns="http://schemas.openxmlformats.org/officeDocument/2006/extended-properties" xmlns:vt="http://schemas.openxmlformats.org/officeDocument/2006/docPropsVTypes">"#,
            "<Application>PosterStudio</Application>",
            "<DocSecurity>0</DocSecurity>",
            "<ScaleCrop>false</ScaleCrop>",
            #"<HeadingPairs><vt:vector size="2" baseType="variant"><vt:variant><vt:lpstr>Worksheets</vt:lpstr></vt:variant><vt:variant><vt:i4>\#(sheetNames.count)</vt:i4></vt:variant></vt:vector></HeadingPairs>"#,
            #"<TitlesOfParts><vt:vector size="\#(sheetNames.count)" baseType="lpstr">\#(titles)</vt:vector></TitlesOfParts>"#,
            "<Company></Company>",
            "<AppVersion>1.0</AppVersion>",
            "</Properties>",
        ].joined()
    }

    private static func coreXML() -> String {
        let formatter = ISO8601DateFormatter()
        let timestamp = formatter.string(from: Date())
        return [
            #"<?xml version="1.0" encoding="UTF-8" standalone="yes"?>"#,
            #"<cp:coreProperties xmlns:cp="http://schemas.openxmlformats.org/package/2006/metadata/core-properties" xmlns:dc="http://purl.org/dc/elements/1.1/" xmlns:dcterms="http://purl.org/dc/terms/" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">"#,
            "<dc:creator>PosterStudio</dc:creator>",
            "<cp:lastModifiedBy>PosterStudio</cp:lastModifiedBy>",
            #"<dcterms:created xsi:type="dcterms:W3CDTF">\#(timestamp)</dcterms:created>"#,
            #"<dcterms:modified xsi:type="dcterms:W3CDTF">\#(timestamp)</dcterms:modified>"#,
            "</cp:coreProperties>",
        ].joined()
    }

    private static func write(_ path: String, in root: URL, contents: String) throws {
        let url = root.appendingPathComponent(path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        guard let data = contents.data(using: .utf8) else {
            throw XlsxError.invalidWorkbook
        }
        try data.write(to: url)
    }

    private static func escapeXML(_ text: String) -> String {
        text
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }

    private static func escapeXMLAttribute(_ text: String) -> String {
        escapeXML(text).replacingOccurrences(of: "\"", with: "&quot;")
    }

    private static func decodeXML(_ text: String) -> String {
        text
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&amp;", with: "&")
    }

    private static func runProcess(executable: String, arguments: [String], currentDirectory: URL?) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.currentDirectoryURL = currentDirectory

        let errorPipe = Pipe()
        process.standardError = errorPipe
        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            let data = errorPipe.fileHandleForReading.readDataToEndOfFile()
            let message = String(data: data, encoding: .utf8) ?? "未知进程错误"
            throw XlsxError.processFailed(message)
        }
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        guard indices.contains(index) else { return nil }
        return self[index]
    }
}
