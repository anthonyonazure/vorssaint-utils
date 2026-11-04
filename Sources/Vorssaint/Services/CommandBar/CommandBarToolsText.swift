// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// Text tools of the quick lookups: encodings, JSON tidying, case changes and
/// the QR code request. All pure; nothing here leaves the Mac.
extension CommandBarTools {
    // MARK: - Encodings

    static let encodingKeywords: Set<String> = [
        "base64", "b64", "unbase64", "b64d", "base64d", "url", "urlencode", "urldecode", "html",
    ]

    private static let urlUnreserved = CharacterSet(
        charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")

    static func encodings(_ key: String, _ rest: String) -> [CommandBarToolAnswer] {
        guard !rest.isEmpty else { return [] }
        var rows: [CommandBarToolAnswer] = []
        func encode(_ id: String, _ value: String?, _ label: String) {
            if let value { rows.append(answer("\(id).encode", value, "→ \(label)", "arrow.right.square")) }
        }
        func decode(_ id: String, _ value: String?, _ label: String) {
            if let value { rows.append(answer("\(id).decode", value, "← \(label)", "arrow.left.square")) }
        }
        switch key {
        case "base64", "b64":
            encode("base64", Data(rest.utf8).base64EncodedString(), "Base64")
            decode("base64", decodeBase64(rest), "Base64")
        case "unbase64", "b64d", "base64d":
            decode("base64", decodeBase64(rest), "Base64")
        case "url":
            encode("url", encodeURLComponent(rest), "URL")
            decode("url", rest.contains("%") ? decodeURLComponent(rest) : nil, "URL")
        case "urlencode":
            encode("url", encodeURLComponent(rest), "URL")
        case "urldecode":
            decode("url", decodeURLComponent(rest), "URL")
        default: // html
            encode("html", escapeHTML(rest), "HTML")
            decode("html", rest.contains("&") && rest.contains(";") ? unescapeHTML(rest) : nil, "HTML")
        }
        return rows
    }

    /// Text only: bytes that are not text, or text full of control
    /// characters, are not an answer, so a plain word that happens to be valid
    /// Base64 never produces a row of nonsense.
    static func decodeBase64(_ text: String) -> String? {
        var cleaned = text.filter { !$0.isWhitespace }
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        guard !cleaned.isEmpty, cleaned.count % 4 != 1,
              cleaned.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || "+/=".contains($0)) })
        else { return nil }
        while cleaned.count % 4 != 0 { cleaned.append("=") }
        guard let data = Data(base64Encoded: cleaned), !data.isEmpty,
              let decoded = String(data: data, encoding: .utf8) else { return nil }
        let controls = decoded.unicodeScalars.filter {
            CharacterSet.controlCharacters.contains($0) && $0 != "\n" && $0 != "\t" && $0 != "\r"
        }
        return controls.isEmpty ? decoded : nil
    }

    static func encodeURLComponent(_ text: String) -> String? {
        text.addingPercentEncoding(withAllowedCharacters: urlUnreserved)
    }

    static func decodeURLComponent(_ text: String) -> String? {
        guard let decoded = text.removingPercentEncoding, decoded != text else { return nil }
        return decoded
    }

    static func escapeHTML(_ text: String) -> String {
        var result = ""
        for character in text {
            switch character {
            case "&": result += "&amp;"
            case "<": result += "&lt;"
            case ">": result += "&gt;"
            case "\"": result += "&quot;"
            case "'": result += "&#39;"
            default: result.append(character)
            }
        }
        return result
    }

    private static let namedEntities: [String: String] = [
        "amp": "&", "lt": "<", "gt": ">", "quot": "\"", "apos": "'", "nbsp": "\u{00A0}",
    ]

    static func unescapeHTML(_ text: String) -> String? {
        guard let expression = try? NSRegularExpression(
            pattern: "&(#[xX][0-9A-Fa-f]{1,6}|#[0-9]{1,7}|[A-Za-z]{2,8});") else { return nil }
        let source = text as NSString
        var result = ""
        var cursor = 0
        var changed = false
        for match in expression.matches(in: text, range: NSRange(location: 0, length: source.length)) {
            result += source.substring(with: NSRange(location: cursor, length: match.range.location - cursor))
            let body = source.substring(with: match.range(at: 1))
            var replacement: String?
            if body.hasPrefix("#") {
                let digits = body.dropFirst()
                let scalar = digits.first == "x" || digits.first == "X"
                    ? UInt32(digits.dropFirst(), radix: 16) : UInt32(digits, radix: 10)
                replacement = scalar.flatMap(Unicode.Scalar.init).map { String(Character($0)) }
            } else {
                replacement = namedEntities[body.lowercased()]
            }
            if let replacement {
                result += replacement
                changed = true
            } else {
                result += source.substring(with: match.range)
            }
            cursor = match.range.location + match.range.length
        }
        result += source.substring(from: cursor)
        return changed ? result : nil
    }

    // MARK: - JSON

    /// Tidy and compact forms of a JSON document. The text is rearranged, never
    /// reparsed, so numbers, key order and escapes come out exactly as typed.
    static func jsonAnswers(_ rest: String) -> [CommandBarToolAnswer] {
        guard let first = rest.first, first == "{" || first == "[",
              let data = rest.data(using: .utf8),
              (try? JSONSerialization.jsonObject(with: data)) != nil else { return [] }
        let pretty = formatJSON(rest, pretty: true)
        let compact = formatJSON(rest, pretty: false)
        var rows = [answer("json.pretty", pretty, "JSON", "curlybraces")]
        if compact != pretty { rows.append(answer("json.compact", compact, "JSON min", "curlybraces")) }
        return rows
    }

    static func formatJSON(_ text: String, pretty: Bool, indent: String = "  ") -> String {
        let characters = Array(text)
        var output = ""
        var depth = 0
        var inString = false
        var escaped = false
        var index = 0
        func newline() {
            output += "\n" + String(repeating: indent, count: max(depth, 0))
        }
        while index < characters.count {
            let character = characters[index]
            if inString {
                output.append(character)
                if escaped {
                    escaped = false
                } else if character == "\\" {
                    escaped = true
                } else if character == "\"" {
                    inString = false
                }
                index += 1
                continue
            }
            switch character {
            case "\"":
                inString = true
                output.append(character)
            case "{", "[":
                output.append(character)
                var next = index + 1
                while next < characters.count, characters[next].isWhitespace { next += 1 }
                if next < characters.count, characters[next] == (character == "{" ? "}" : "]") {
                    output.append(characters[next])
                    index = next
                } else if pretty {
                    depth += 1
                    newline()
                }
            case "}", "]":
                if pretty {
                    depth -= 1
                    newline()
                }
                output.append(character)
            case ",":
                output.append(character)
                if pretty { newline() }
            case ":":
                output.append(character)
                if pretty { output.append(" ") }
            default:
                if !character.isWhitespace { output.append(character) }
            }
            index += 1
        }
        return output
    }

    // MARK: - Case changes

    static let caseKeywords: Set<String> = [
        "upper", "lower", "title", "snake", "camel", "pascal", "kebab", "constant", "case",
    ]

    /// The words of a name written in any style: "myHTTPServer_v2" is
    /// my, HTTP, Server, v2.
    static func words(in text: String) -> [String] {
        let characters = Array(text)
        var words: [String] = []
        var current = ""
        for (index, character) in characters.enumerated() {
            guard character.isLetter || character.isNumber else {
                if !current.isEmpty { words.append(current); current = "" }
                continue
            }
            if !current.isEmpty, character.isUppercase, index > 0 {
                let previous = characters[index - 1]
                let nextIsLower = index + 1 < characters.count && characters[index + 1].isLowercase
                if previous.isLowercase || (previous.isUppercase && nextIsLower) {
                    words.append(current)
                    current = ""
                }
            }
            current.append(character)
        }
        if !current.isEmpty { words.append(current) }
        return words
    }

    private static func capitalized(_ word: String) -> String {
        word.prefix(1).uppercased() + word.dropFirst().lowercased()
    }

    static func caseAnswers(_ key: String, _ rest: String) -> [CommandBarToolAnswer] {
        let parts = words(in: rest)
        guard !parts.isEmpty else { return [] }
        func row(_ id: String, _ label: String, _ value: String) -> CommandBarToolAnswer {
            answer("case.\(id)", value, label, "textformat")
        }
        let snake = row("snake", "snake_case", parts.map { $0.lowercased() }.joined(separator: "_"))
        let camel = row("camel", "camelCase",
                        parts[0].lowercased() + parts.dropFirst().map(capitalized).joined())
        let pascal = row("pascal", "PascalCase", parts.map(capitalized).joined())
        let kebab = row("kebab", "kebab-case", parts.map { $0.lowercased() }.joined(separator: "-"))
        let constant = row("constant", "CONSTANT_CASE", parts.map { $0.uppercased() }.joined(separator: "_"))
        let title = row("title", "Title Case", parts.map(capitalized).joined(separator: " "))
        switch key {
        case "upper": return [row("upper", "UPPER", rest.uppercased())]
        case "lower": return [row("lower", "lower", rest.lowercased())]
        case "title": return [title]
        case "snake": return [snake]
        case "camel": return [camel]
        case "pascal": return [pascal]
        case "kebab": return [kebab]
        case "constant": return [constant]
        default: return [snake, camel, pascal, kebab, constant, title]
        }
    }

    // MARK: - Word definitions

    /// The word of "define serendipity", "def don't". The lookup itself runs in
    /// the background, so this only says whether the text asks for one.
    static func definitionWord(for query: String) -> String? {
        let (key, rest) = split(query.trimmingCharacters(in: .whitespacesAndNewlines))
        guard ["define", "def", "meaning"].contains(key.lowercased()),
              (2...40).contains(rest.count),
              rest.allSatisfy({ $0.isLetter || $0 == "'" || $0 == "\u{2019}" || $0 == "-" }),
              rest.contains(where: \.isLetter) else { return nil }
        return rest
    }

    // MARK: - QR code

    static let maxQRLength = 1_000

    /// The request only: the image is drawn when Return is pressed.
    static func qr(_ rest: String) -> [CommandBarToolAnswer] {
        guard !rest.isEmpty, rest.count <= maxQRLength else { return [] }
        return [answer("qr", rest, "QR", "qrcode", action: .copyQRCode)]
    }
}
