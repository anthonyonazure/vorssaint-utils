// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// What the command bar remembers when asked to, and what it never keeps.
enum CommandBarRecallTests {
    static func run(_ suite: TestSuite) {
        recents(suite)
        history(suite)
    }

    private static func recents(_ suite: TestSuite) {
        var keys: [String] = []
        for key in ["a", "b", "c"] { keys = CommandBarRecents.recording(key, in: keys) }
        suite.expect(keys == ["c", "b", "a"], "the newest command leads")
        keys = CommandBarRecents.recording("a", in: keys)
        suite.expect(keys == ["a", "c", "b"], "running a command again moves it to the front, once")
        for index in 0..<30 { keys = CommandBarRecents.recording("k\(index)", in: keys) }
        suite.expect(keys.count == CommandBarRecents.storedLimit && keys.first == "k29",
                     "only the latest ten are kept")
        suite.expect(CommandBarRecents.recording("", in: ["a"]) == ["a"]
                     && CommandBarRecents.recording("x\ny", in: ["a"]) == ["a"],
                     "an empty key or one with a line break is never stored")
        suite.expect(CommandBarRecents.decode(CommandBarRecents.encode(["x", "y", "x", " "])) == ["x", "y"],
                     "stored text round-trips and drops repeats and blanks")

        let shown = CommandBarRecents.visible(["a", "gone", "b", "c", "d", "e", "f", "g"],
                                              available: ["a", "b", "c", "d", "e", "f", "g"],
                                              excluding: ["c"])
        suite.expect(shown == ["a", "b", "d", "e", "f"],
                     "the bar shows five, skipping what no longer exists and what is pinned: \(shown)")

        suite.expect(CommandBarRecents.mayRemember(rowID: "app.com.apple.Safari")
                     && CommandBarRecents.mayRemember(rowID: "action.screenshot")
                     && CommandBarRecents.mayRemember(rowID: "settings.general"),
                     "apps, actions and Settings pages are remembered")
        for id in ["window.123", "menu.File.Save", "clipboard.4", "emoji.fire", "tool.dice", "math.result",
                   "file.abc", "kill.99", "selection.copy", "quit.com.apple.Safari"] {
            suite.expect(!CommandBarRecents.mayRemember(rowID: id), "\(id) is never remembered")
        }
    }

    private static func history(_ suite: TestSuite) {
        var searches: [String] = []
        for query in ["safari", "100 km to mi", "Safari"] {
            searches = CommandBarSearchHistory.recording(query, in: searches)
        }
        suite.expect(searches == ["Safari", "100 km to mi"],
                     "a repeat in any case replaces the older one: \(searches)")
        for index in 0..<40 { searches = CommandBarSearchHistory.recording("query \(index)", in: searches) }
        suite.expect(searches.count == CommandBarSearchHistory.storedLimit && searches.first == "query 39",
                     "only the latest twenty are kept")

        for secret in ["password 20", "pw", "PASSWORD 12", "sha256 hunter2", "md5 secret", "hash my token",
                       "base64 c2VjcmV0", "unbase64 abc", "url a b", "html <b>", "json {\"k\":1}",
                       "qr https://example.com", "snake my secret thing", "case helloWorld"] {
            suite.expect(!CommandBarSearchHistory.mayRemember(secret), "\"\(secret)\" is never kept")
        }
        for plain in ["roll 2d6", "time tokyo", "hex ff", "safari", "100 km to mi", "ab"] {
            suite.expect(CommandBarSearchHistory.mayRemember(plain), "\"\(plain)\" can be kept")
        }
        for bad in ["", " ", "a", "?", String(repeating: "x", count: 121), "two\nlines"] {
            suite.expect(!CommandBarSearchHistory.mayRemember(bad), "\"\(bad.prefix(20))\" is not kept")
        }
        suite.expect(CommandBarSearchHistory.recording("sha256 abc", in: ["x1"]) == ["x1"],
                     "recording a secret changes nothing")
        suite.expect(CommandBarSearchHistory.decode("A b\na B\nc d\n\n") == ["A b", "c d"],
                     "stored searches drop repeats in any case and blanks")

        typealias History = CommandBarSearchHistory
        suite.expect(History.step(from: nil, .older, count: 3) == 0
                     && History.step(from: 0, .older, count: 3) == 1
                     && History.step(from: 2, .older, count: 3) == 2,
                     "going back stops at the oldest")
        suite.expect(History.step(from: 2, .newer, count: 3) == 1 && History.step(from: 1, .newer, count: 3) == 0
                     && History.step(from: 0, .newer, count: 3) == nil
                     && History.step(from: nil, .newer, count: 3) == nil,
                     "going forward from the newest returns to what was being typed")
        suite.expect(History.step(from: nil, .older, count: 0) == nil, "an empty history goes nowhere")
    }
}
