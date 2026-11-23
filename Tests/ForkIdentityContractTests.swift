// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint
//
// macArmyKnife: new in the macArmyKnife fork on 2026-11-23. Guards the thin
// layer that renames the app, so an upstream merge that moves the code it
// hooks into turns the sync red instead of silently shipping a build that
// could self-update into the official app.

import Foundation

enum ForkIdentityContractTests {
    static func run(_ suite: TestSuite) {
        suite.run("fork identity: tests compile as upstream") {
            suite.expect(!ForkIdentity.isActive, "the test build must not define MACARMYKNIFE")
            suite.expect(ForkIdentity.allowsSelfUpdate && ForkIdentity.allowsFeedback,
                         "upstream builds keep the updater and feedback")
            suite.expect(AppInfo.name == "Vorssaint", "upstream builds keep their name")
        }

        suite.run("fork identity: own bundle ids") {
            let own = ForkIdentity.bundleID
            suite.expect(ForkIdentity.isOwnBundleID(own), "the app itself")
            suite.expect(ForkIdentity.isOwnBundleID(own + ".fan-control"), "its fan helper")
            suite.expect(ForkIdentity.isOwnBundleID(own.uppercased()), "any letter case")
            suite.expect(!ForkIdentity.isOwnBundleID(own + "x"), "a longer id is someone else")
            suite.expect(!ForkIdentity.isOwnBundleID(nil), "no id")
            suite.expect(!ForkIdentity.isOwnBundleID("com.vorssaint.utils"), "Vorssaint is not the fork")
        }

        suite.run("fork identity: protections cover macArmyKnife and keep Vorssaint") {
            for id in [ForkIdentity.bundleID, "com.vorssaint.utils", "com.vorssaint.utils.dev"] {
                suite.expect(DockClickSupport.isOwnBundleIdentifier(id), "Dock click skips \(id)")
                suite.expect(QuickTogglesSupport.vorssaintBundleIdentifiers.contains(id),
                             "Quit all spares \(id)")
                suite.expect(CleanerSupport.isProtectedBundleID(id), "Cleaner protects \(id)")
                suite.expect(StartupItemSupport.isLocked(id + ".fan-control"),
                             "Startup items lock \(id).fan-control")
                suite.expect(CleanerPolicy.isExcludedCacheEntry(id), "Cleaner hides the \(id) cache")
            }
            let uninstaller = source("Sources/Vorssaint/Services/Uninstall/UninstallerSupport.swift")
            suite.expect(body(of: "private static func isOwnBundleID(", in: uninstaller)
                            .contains("ForkIdentity.isOwnBundleID("),
                         "the uninstaller refuses macArmyKnife as this app")
        }

        suite.run("fork identity: updater gated at every entry") {
            let update = source("Sources/Vorssaint/Services/Update/UpdateService.swift")
            for entry in ["func startAutomaticChecks()", "func check(manual: Bool)",
                          "func checkIfStale(", "func downloadAndInstall()",
                          "private func launchInstaller("] {
                suite.expect(firstStatement(after: entry, in: update)
                                .hasPrefix("guard ForkIdentity.allowsSelfUpdate else { return }"),
                             "UpdateService \(entry) starts with the macArmyKnife gate")
            }
            let settings = source("Sources/Vorssaint/UI/Settings/SettingsView.swift")
            suite.expect(settings.contains("if ForkIdentity.allowsSelfUpdate {\n                UpdatesView()"),
                         "About hides the update controls in macArmyKnife")
        }

        suite.run("fork identity: feedback stays local") {
            let delegate = source("Sources/Vorssaint/App/AppDelegate.swift")
            suite.expect(body(of: "func openFeedbackWindow(", in: delegate)
                            .contains("guard ForkIdentity.allowsFeedback else"),
                         "the feedback window is not offered in macArmyKnife")
            let service = source("Sources/Vorssaint/Services/Feedback/FeedbackService.swift")
            suite.expect(body(of: "func submit(", in: service)
                            .contains("guard ForkIdentity.allowsFeedback else"),
                         "feedback is never posted from macArmyKnife")
        }

        suite.run("fork identity: one bundle id everywhere") {
            let id = ForkIdentity.bundleID
            let build = source("build.sh")
            suite.expect(build.contains("APP_BUNDLE_ID=\"\(id)\""), "build.sh --mak stamps \(id)")
            suite.expect(build.contains("BUILD_VARIANT_FLAGS=(-D MACARMYKNIFE)"),
                         "build.sh --mak compiles the fork identity")
            let fan = source("Sources/Vorssaint/Services/FanControl/FanControlXPC.swift")
            suite.expect(fan.contains("#if MACARMYKNIFE\n    // Same value as ForkIdentity.bundleID, which the helper does not compile.\n    static let appBundleID = \"\(id)\""),
                         "the fan helper trusts \(id)")
            suite.expect(fan.components(separatedBy: "#if VORSSAINT_DEVELOPMENT || MACARMYKNIFE").count - 1 == 4,
                         "the fan helper pins the self-signed certificate for macArmyKnife")
        }
    }

    private static func source(_ path: String) -> String {
        (try? String(contentsOfFile: path, encoding: .utf8)) ?? ""
    }

    /// The text from `signature` to the end of its body, by brace depth.
    private static func body(of signature: String, in source: String) -> String {
        guard let start = source.range(of: signature) else { return "" }
        var depth = 0
        var opened = false
        var index = start.lowerBound
        while index < source.endIndex {
            let character = source[index]
            if character == "{" { depth += 1; opened = true }
            if character == "}" { depth -= 1 }
            index = source.index(after: index)
            if opened && depth == 0 { break }
        }
        return String(source[start.lowerBound..<index])
    }

    /// The first non-empty line inside the body that `signature` opens.
    private static func firstStatement(after signature: String, in source: String) -> String {
        let lines = body(of: signature, in: source).components(separatedBy: "\n").dropFirst()
        return lines.first { !$0.trimmingCharacters(in: .whitespaces).isEmpty }?
            .trimmingCharacters(in: .whitespaces) ?? ""
    }
}
