// IPMsgX/Views/MessageRenderer.swift
// Renders IP Messenger message text into AttributedString with:
//   1. Inline markdown (bold, italic, code, explicit [text](url) links)
//   2. Bare URL detection via NSDataDetector → clickable links
//   3. Protocol-separator stripping (NUL / BEL chars from Windows IPMSG)

import Foundation
import SwiftUI

enum MessageRenderer {

    // MARK: - Sanitize

    /// Strip IP Messenger protocol separators embedded in the message text.
    /// Some Windows IPMSG clients embed attachment metadata directly in the
    /// appendix without a NUL separator, producing text like
    /// "\x000:Dance.mp4:F6B79D:69621397:1:\x00". Truncate at the first
    /// control separator so only the human-readable portion is displayed.
    static func sanitize(_ raw: String) -> String {
        var text = raw
        if let idx = text.firstIndex(where: { $0 == "\0" || $0 == "\u{07}" }) {
            text = String(text[..<idx])
        }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Render

    /// Produce a SwiftUI-renderable AttributedString from raw message text.
    ///
    /// The markdown pipeline is only engaged when the text actually contains
    /// markdown syntax characters or a URL. Skipping it for plain text and
    /// emoji avoids a Foundation bug where `AttributedString(markdown:)` can
    /// produce zero-height / invisible runs for certain Unicode/emoji sequences,
    /// even with `.inlineOnlyPreservingWhitespace`.
    static func render(_ raw: String) -> AttributedString {
        let text = sanitize(raw)
        guard !text.isEmpty else { return AttributedString("") }

        let needsMarkdown = text.contains("*") || text.contains("`")
                         || text.contains("~~") || text.contains("[")
        let needsLinkify  = text.contains("http://") || text.contains("https://")

        // Fast path: plain text and emoji — no markdown processing needed.
        guard needsMarkdown || needsLinkify else {
            return AttributedString(text)
        }

        let preprocessed = needsLinkify ? linkifyBareURLs(in: text) : text

        if let attributed = try? AttributedString(
            markdown: preprocessed,
            options: AttributedString.MarkdownParsingOptions(
                interpretedSyntax: .inlineOnlyPreservingWhitespace
            )
        ) {
            return attributed
        }

        // Fallback: plain text (no crash even if markdown throws)
        return AttributedString(text)
    }

    // MARK: - Private helpers

    /// Replace bare URLs with `[url](url)` markdown so AttributedString
    /// creates clickable link runs for them. Processes matches in reverse
    /// order so earlier-match offsets remain valid after each replacement.
    private static func linkifyBareURLs(in text: String) -> String {
        guard let detector = try? NSDataDetector(
            types: NSTextCheckingResult.CheckingType.link.rawValue
        ) else { return text }

        let fullRange = NSRange(text.startIndex..., in: text)
        let matches = detector.matches(in: text, options: [], range: fullRange)
        guard !matches.isEmpty else { return text }

        var result = text
        for match in matches.reversed() {
            guard let url = match.url,
                  let range = Range(match.range, in: result) else { continue }

            // Skip URLs that are already inside a markdown link target `](...)`
            if range.lowerBound > result.startIndex,
               result[result.index(before: range.lowerBound)] == "(" {
                continue
            }

            let urlStr = String(result[range])
            result.replaceSubrange(range, with: "[\(urlStr)](\(url.absoluteString))")
        }
        return result
    }
}
