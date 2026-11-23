// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint
//
// macArmyKnife: modified by anthonyonazure on 2026-11-23. This file is new in
// the macArmyKnife fork; see MACARMYKNIFE.md for what the fork changes.

import Foundation

/// Identity of macArmyKnife, a personal, renamed build of Vorssaint.
///
/// `./build.sh --mak` compiles with `-D MACARMYKNIFE` and stamps the bundle
/// with `bundleID`; every other build (official, Developer, tests) leaves
/// `isActive` false and behaves exactly as upstream Vorssaint. Upstream's
/// trademark policy asks forks for their own name, icon, bundle id, signing
/// identity and update feed; this is where the code side of that lives.
enum ForkIdentity {
    #if MACARMYKNIFE
    static let isActive = true
    #else
    static let isActive = false
    #endif

    static let name = "macArmyKnife"
    /// Keep in sync with APP_BUNDLE_ID for `--mak` in build.sh and with
    /// FanControlIdentifiers, which the fan helper compiles on its own.
    static let bundleID = "io.github.anthonyonazure.macarmyknife"
    static let sourceURL = URL(string: "https://github.com/anthonyonazure/vorssaint-utils/tree/mak/main")!
    static let upstreamURL = URL(string: "https://github.com/vorssaint/vorssaint-utils")!
    /// GPL section 5: a modified work carries a notice saying so.
    static let notice = "Based on Vorssaint © 2026 Vorssaint · GPL-3.0-or-later · modified by anthonyonazure"

    /// The built-in updater only knows the official Vorssaint releases, and its
    /// installer accepts the official signature, so leaving it on would put the
    /// official app in place of this one. macArmyKnife takes upstream releases
    /// through scripts/sync-upstream.sh instead.
    static var allowsSelfUpdate: Bool { !isActive }

    /// Feedback is posted to the upstream maintainer's server; reports about a
    /// modified build do not belong there.
    static var allowsFeedback: Bool { !isActive }

    /// macArmyKnife's own bundle and the helpers named under it. Callers that
    /// protect "this app" keep their Vorssaint checks as well: the official
    /// and Developer apps, and their data, stay installed next to this one.
    static func isOwnBundleID(_ id: String?) -> Bool {
        guard let lowered = id?.lowercased() else { return false }
        return lowered == bundleID || lowered.hasPrefix(bundleID + ".")
    }
}
