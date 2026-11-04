// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import CoreImage

/// Draws the QR code for a piece of text, entirely on this Mac.
enum CommandBarQRCode {
    /// Black on white with a quiet margin, which scanners need to find the
    /// code. Nil when the text cannot be encoded.
    static func image(for text: String) -> NSImage? {
        guard !text.isEmpty, let filter = CIFilter(name: "CIQRCodeGenerator") else { return nil }
        filter.setValue(Data(text.utf8), forKey: "inputMessage")
        filter.setValue("M", forKey: "inputCorrectionLevel")
        guard let output = filter.outputImage else { return nil }
        let scaled = output.transformed(by: CGAffineTransform(scaleX: 10, y: 10))
        let padded = scaled.extent.insetBy(dx: -40, dy: -40)
        let background = CIImage(color: .white).cropped(to: padded)
        let composed = scaled.composited(over: background)
        guard let rendered = CIContext().createCGImage(composed, from: padded) else { return nil }
        return NSImage(cgImage: rendered,
                       size: NSSize(width: padded.width / 2, height: padded.height / 2))
    }
}
