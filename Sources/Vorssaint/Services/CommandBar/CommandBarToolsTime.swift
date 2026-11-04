// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// Time zones for the quick lookups: "time tokyo", "3pm new york to london".
/// Everything comes from the zone database that ships with macOS.
extension CommandBarTools {
    struct Place: Equatable {
        let zone: TimeZone
        let name: String
    }

    /// Names people type that the zone database does not use. The zones named
    /// by region follow daylight saving, so "est" in July is Eastern Daylight
    /// time, the way people mean it.
    private static let zoneAliases: [String: String] = [
        "utc": "UTC", "gmt": "GMT", "z": "UTC",
        "est": "America/New_York", "edt": "America/New_York", "et": "America/New_York",
        "eastern": "America/New_York", "nyc": "America/New_York",
        "cst": "America/Chicago", "cdt": "America/Chicago", "ct": "America/Chicago",
        "central": "America/Chicago",
        "mst": "America/Denver", "mdt": "America/Denver", "mt": "America/Denver",
        "mountain": "America/Denver",
        "arizona": "America/Phoenix", "phoenix": "America/Phoenix",
        "pst": "America/Los_Angeles", "pdt": "America/Los_Angeles", "pt": "America/Los_Angeles",
        "pacific": "America/Los_Angeles", "la": "America/Los_Angeles", "sf": "America/Los_Angeles",
        "akst": "America/Anchorage", "akdt": "America/Anchorage", "alaska": "America/Anchorage",
        "hst": "Pacific/Honolulu", "hawaii": "Pacific/Honolulu",
        "uk": "Europe/London", "bst": "Europe/London",
        "cet": "Europe/Paris", "cest": "Europe/Paris",
        "eet": "Europe/Athens", "eest": "Europe/Athens",
        "ist": "Asia/Kolkata", "india": "Asia/Kolkata", "mumbai": "Asia/Kolkata", "delhi": "Asia/Kolkata",
        "china": "Asia/Shanghai", "beijing": "Asia/Shanghai",
        "jst": "Asia/Tokyo", "japan": "Asia/Tokyo",
        "kst": "Asia/Seoul", "korea": "Asia/Seoul",
        "aest": "Australia/Sydney", "aedt": "Australia/Sydney",
        "nzst": "Pacific/Auckland", "nzdt": "Pacific/Auckland",
    ]

    private static func cityName(of identifier: String) -> String {
        (identifier.split(separator: "/").last.map(String.init) ?? identifier)
            .replacingOccurrences(of: "_", with: " ")
    }

    private static let zonesByCity: [String: String] = {
        var map: [String: String] = [:]
        for identifier in TimeZone.knownTimeZoneIdentifiers.sorted() {
            let key = cityName(of: identifier).lowercased()
            if map[key] == nil { map[key] = identifier }
        }
        return map
    }()

    static func resolvePlace(_ text: String) -> Place? {
        let key = text.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty, key.count <= 40 else { return nil }
        func place(_ identifier: String, _ label: String? = nil) -> Place? {
            TimeZone(identifier: identifier).map { Place(zone: $0, name: label ?? cityName(of: identifier)) }
        }
        if let alias = zoneAliases[key] { return place(alias, key.count <= 4 ? key.uppercased() : nil) }
        if let identifier = zonesByCity[key] { return place(identifier) }
        if let zone = TimeZone(identifier: text.trimmingCharacters(in: .whitespaces)) {
            return Place(zone: zone, name: cityName(of: zone.identifier))
        }
        guard key.count >= 3 else { return nil }
        let match = zonesByCity.keys.filter { $0.hasPrefix(key) }.sorted().first
        return match.flatMap { zonesByCity[$0] }.flatMap { place($0) }
    }

    /// "3pm", "3 pm", "3:30pm", "15:00", "noon", "midnight". Without am or pm
    /// a colon is required, so a bare number is never taken for a time.
    static func parseClock(_ text: String) -> (hour: Int, minute: Int)? {
        var value = text.lowercased().filter { !$0.isWhitespace }
        switch value {
        case "noon": return (12, 0)
        case "midnight": return (0, 0)
        default: break
        }
        var meridiem: String?
        for suffix in ["am", "pm"] where value.hasSuffix(suffix) {
            meridiem = suffix
            value.removeLast(2)
        }
        let parts = value.split(separator: ":", omittingEmptySubsequences: false).map(String.init)
        guard (1...2).contains(parts.count), parts.allSatisfy({ !$0.isEmpty && $0.count <= 2 && $0.allSatisfy(\.isASCII) && $0.allSatisfy(\.isNumber) }),
              var hour = Int(parts[0]) else { return nil }
        let minute = parts.count == 2 ? (Int(parts[1]) ?? -1) : 0
        guard (0...59).contains(minute) else { return nil }
        if let meridiem {
            guard (1...12).contains(hour) else { return nil }
            hour = hour % 12 + (meridiem == "pm" ? 12 : 0)
        } else {
            guard parts.count == 2, (0...23).contains(hour) else { return nil }
        }
        return (hour, minute)
    }

    /// A leading clock, with the rest of the words left over.
    private static func leadingClock(_ words: [String]) -> (clock: (hour: Int, minute: Int), rest: [String])? {
        if let first = words.first, let clock = parseClock(first) { return (clock, Array(words.dropFirst())) }
        if words.count >= 2, let clock = parseClock(words[0] + words[1]) {
            return (clock, Array(words.dropFirst(2)))
        }
        return nil
    }

    private static func dayNumber(_ date: Date, in zone: TimeZone) -> Int {
        Int(((date.timeIntervalSince1970 + Double(zone.secondsFromGMT(for: date))) / 86_400).rounded(.down))
    }

    private static func localPlace(_ context: Context) -> Place {
        Place(zone: context.localTimeZone, name: cityName(of: context.localTimeZone.identifier))
    }

    private static func timeAnswer(_ instant: Date, from source: Place, to target: Place,
                                   _ context: Context) -> CommandBarToolAnswer {
        let formatter = DateFormatter()
        formatter.locale = context.locale
        formatter.timeZone = target.zone
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        var detail = target.name
        if let abbreviation = target.zone.abbreviation(for: instant), abbreviation != target.name {
            detail += " · " + abbreviation
        }
        let delta = dayNumber(instant, in: target.zone) - dayNumber(instant, in: source.zone)
        if delta != 0 { detail += " · " + (delta > 0 ? "+" : "") + "\(delta)d" }
        return answer("time", formatter.string(from: instant), detail, "clock")
    }

    private static func instant(of clock: (hour: Int, minute: Int), in source: Place,
                                _ context: Context) -> Date? {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = source.zone
        var day = calendar.dateComponents([.year, .month, .day], from: context.now)
        day.hour = clock.hour
        day.minute = clock.minute
        return calendar.date(from: day)
    }

    /// "tokyo", "3pm tokyo", "3pm new york to tokyo", "3pm to tokyo". With
    /// `requireFull` only the last form, with a place on both sides, answers:
    /// that is the one safe to read without the keyword.
    static func timeConversion(_ text: String, requireFull: Bool,
                               _ context: Context) -> [CommandBarToolAnswer] {
        let lowered = text.lowercased()
        var left = lowered
        var right: String?
        for separator in [" to ", " in ", "->"] {
            if let range = lowered.range(of: separator) {
                left = String(lowered[..<range.lowerBound])
                right = String(lowered[range.upperBound...])
                break
            }
        }
        let leftWords = left.split(whereSeparator: \.isWhitespace).map(String.init)
        let parsed = leadingClock(leftWords)
        let placeWords = parsed?.rest ?? leftWords
        let leftPlace = placeWords.isEmpty ? nil : resolvePlace(placeWords.joined(separator: " "))
        if !placeWords.isEmpty, leftPlace == nil { return [] }

        if let right {
            guard let target = resolvePlace(right) else { return [] }
            let source = leftPlace ?? localPlace(context)
            if requireFull, leftPlace == nil || parsed == nil { return [] }
            if let clock = parsed?.clock {
                guard let moment = instant(of: clock, in: source, context) else { return [] }
                return [timeAnswer(moment, from: source, to: target, context)]
            }
            return [timeAnswer(context.now, from: source, to: target, context)]
        }
        if requireFull { return [] }
        guard let place = leftPlace else { return [] }
        if let clock = parsed?.clock {
            guard let moment = instant(of: clock, in: place, context) else { return [] }
            return [timeAnswer(moment, from: place, to: localPlace(context), context)]
        }
        return [timeAnswer(context.now, from: localPlace(context), to: place, context)]
    }

    static func time(_ rest: String, _ context: Context) -> [CommandBarToolAnswer] {
        rest.isEmpty ? [] : timeConversion(rest, requireFull: false, context)
    }

    static func zoneConversion(_ text: String, _ context: Context) -> [CommandBarToolAnswer] {
        timeConversion(text, requireFull: true, context)
    }
}
