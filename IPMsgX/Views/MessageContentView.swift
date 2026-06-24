// IPMsgX/Views/MessageContentView.swift
// Renders message text with block-level support: contiguous lines beginning with ">"
// are shown as a styled blockquote; everything else uses the inline markdown renderer.

import SwiftUI

struct MessageContentView: View {
    let raw: String

    var body: some View {
        let blocks = Self.parseBlocks(MessageRenderer.sanitize(raw))
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                switch block {
                case .text(let text):
                    Text(MessageRenderer.render(text))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                case .quote(let text):
                    HStack(alignment: .top, spacing: 8) {
                        RoundedRectangle(cornerRadius: 1.5)
                            .fill(Color.secondary.opacity(0.45))
                            .frame(width: 3)
                        Text(MessageRenderer.render(text))
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    // MARK: - Block parsing

    enum Block {
        case text(String)
        case quote(String)
    }

    /// Group consecutive `>`-prefixed lines into quote blocks; the rest into text blocks.
    static func parseBlocks(_ message: String) -> [Block] {
        let lines = message.components(separatedBy: "\n")
        var blocks: [Block] = []
        var buffer: [String] = []
        var bufferIsQuote = false

        func flush() {
            guard !buffer.isEmpty else { return }
            let joined = buffer.joined(separator: "\n")
            blocks.append(bufferIsQuote ? .quote(joined) : .text(joined))
            buffer.removeAll()
        }

        for line in lines {
            let isQuote = line.first == ">"
            if isQuote != bufferIsQuote {
                flush()
                bufferIsQuote = isQuote
            }
            // Strip the leading "> " (or ">") marker for quote lines.
            if isQuote {
                var stripped = String(line.dropFirst())
                if stripped.first == " " { stripped.removeFirst() }
                buffer.append(stripped)
            } else {
                buffer.append(line)
            }
        }
        flush()
        return blocks
    }
}
