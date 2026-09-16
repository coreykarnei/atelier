import AppKit

/// Rendered markdown for the editor's Preview mode (M2.6). Foundation parses
/// (`AttributedString(markdown:)`, full syntax — headings, lists, quotes,
/// code blocks, tables, links); this view lays the blocks out and dresses
/// them in Mocha: two-voice type (ui for prose, mono for code), the
/// content type scale, translucent like the buffer it stands in for.
/// Read-only and selectable; copy gives you the rendered text.
final class MarkdownPreviewView: NSView {
    private let scroll = NSScrollView()
    private let textView = NSTextView()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = Theme.Elevation.base.cgColor

        textView.isEditable = false
        textView.isSelectable = true
        textView.drawsBackground = false
        textView.isRichText = true
        textView.textContainerInset = NSSize(width: 18, height: 14)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        textView.linkTextAttributes = [
            .foregroundColor: Theme.accentBlue,
            .underlineStyle: NSUnderlineStyle.single.rawValue,
            .cursor: NSCursor.pointingHand,
        ]

        scroll.documentView = textView
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        scroll.scrollerStyle = .overlay
        scroll.translatesAutoresizingMaskIntoConstraints = false
        addSubview(scroll)
        NSLayoutConstraint.activate([
            scroll.topAnchor.constraint(equalTo: topAnchor),
            scroll.leadingAnchor.constraint(equalTo: leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: trailingAnchor),
            scroll.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func updateLayer() {
        layer?.backgroundColor = Theme.Elevation.base.cgColor
    }

    /// Replace the rendering, keeping the scroll position when the document
    /// merely changed under you (live preview while typing).
    func render(markdown: String) {
        let origin = scroll.contentView.bounds.origin
        textView.textStorage?.setAttributedString(Self.render(markdown))
        textView.layoutManager?.ensureLayout(for: textView.textContainer!)
        scroll.contentView.scroll(to: origin)
        scroll.reflectScrolledClipView(scroll.contentView)
    }

    // MARK: Rendering

    private static func render(_ markdown: String) -> NSAttributedString {
        let options = AttributedString.MarkdownParsingOptions(
            allowsExtendedAttributes: true,
            interpretedSyntax: .full,
            failurePolicy: .returnPartiallyParsedIfPossible
        )
        guard let parsed = try? AttributedString(markdown: markdown, options: options) else {
            return NSAttributedString(string: markdown, attributes: bodyAttributes())
        }

        let out = NSMutableAttributedString()
        var lastBlock: Int? = nil
        var lastListItem: Int? = nil
        var lastRow: Int? = nil
        func find(_ components: [PresentationIntent.IntentType], _ test: (PresentationIntent.Kind) -> Bool) -> Int? {
            components.first(where: { test($0.kind) })?.identity
        }

        for run in parsed.runs {
            let text = String(parsed[run.range].characters)
            let components = run.presentationIntent?.components ?? []
            let block = components.first?.identity

            // Block boundaries: a blank line between blocks; list items and
            // table cells get their own separators.
            let row = find(components) { if case .tableRow = $0 { return true }; if case .tableHeaderRow = $0 { return true }; return false }
            let listItem = find(components) { if case .listItem = $0 { return true }; return false }
            if let lastBlock, block != lastBlock {
                if let row, row == lastRow {
                    out.append(NSAttributedString(string: "  │  ", attributes: mutedMono())) // next cell, same row
                } else if row != nil, lastRow != nil {
                    out.append(NSAttributedString(string: "\n", attributes: bodyAttributes())) // next row
                } else if listItem != nil, lastListItem != nil {
                    out.append(NSAttributedString(string: "\n", attributes: bodyAttributes()))
                } else {
                    out.append(NSAttributedString(string: "\n\n", attributes: bodyAttributes()))
                }
            }

            var attributes = bodyAttributes()
            var prefix = ""
            var isCode = false
            var depth = 0
            var quote = false
            var isHeading = false

            for component in components.reversed() { // outermost first
                switch component.kind {
                case .header(let level):
                    isHeading = true
                    attributes[.font] = headingFont(level)
                    attributes[.foregroundColor] = level <= 2 ? Theme.Editor.text : Theme.chromeSelectedText
                case .codeBlock:
                    isCode = true
                    attributes[.font] = Theme.Typography.mono(Theme.TypeScale.current - 1)
                    attributes[.backgroundColor] = Theme.Elevation.surface0
                    attributes[.foregroundColor] = Theme.Editor.text
                case .blockQuote:
                    quote = true
                    attributes[.foregroundColor] = Theme.chromeText
                    attributes[.obliqueness] = 0.12
                case .unorderedList, .orderedList:
                    depth += 1
                case .listItem(let ordinal):
                    if component.identity != lastListItem {
                        let ordered = components.contains { if case .orderedList = $0.kind { return true }; return false }
                        prefix = ordered ? "\(ordinal). " : "•  "
                    }
                case .thematicBreak:
                    attributes[.foregroundColor] = Theme.Elevation.surface1
                case .tableHeaderRow:
                    attributes[.font] = Theme.Typography.ui(Theme.TypeScale.current, weight: .semibold)
                default:
                    break
                }
            }

            // Paragraph geometry: indent lists and quotes, breathe between blocks.
            let paragraph = NSMutableParagraphStyle()
            paragraph.lineSpacing = isCode ? 1 : 3
            paragraph.paragraphSpacing = 0
            let indent: CGFloat = CGFloat(depth) * 18 + (quote ? 14 : 0)
            paragraph.firstLineHeadIndent = indent
            paragraph.headIndent = indent + (prefix.isEmpty ? 0 : 18)
            if isHeading { paragraph.paragraphSpacingBefore = 6 }
            attributes[.paragraphStyle] = paragraph

            // Inline voice.
            if let inline = run.inlinePresentationIntent {
                if inline.contains(.code) {
                    attributes[.font] = Theme.Typography.mono(Theme.TypeScale.current - 1)
                    attributes[.foregroundColor] = Theme.Editor.string
                    attributes[.backgroundColor] = Theme.Elevation.surface0
                }
                if inline.contains(.stronglyEmphasized) {
                    attributes[.font] = boldened(attributes[.font] as? NSFont)
                }
                if inline.contains(.emphasized) {
                    attributes[.obliqueness] = 0.15
                }
                if inline.contains(.strikethrough) {
                    attributes[.strikethroughStyle] = NSUnderlineStyle.single.rawValue
                }
            }
            if let link = run.link {
                attributes[.link] = link
            }

            if quote, block != lastBlock {
                out.append(NSAttributedString(string: "▎ ", attributes: [
                    .foregroundColor: Theme.Elevation.surface1,
                    .font: Theme.Typography.ui(Theme.TypeScale.current),
                    .paragraphStyle: paragraph,
                ]))
            }
            if !prefix.isEmpty {
                var prefixAttrs = attributes
                prefixAttrs[.foregroundColor] = Theme.chromeMutedText
                out.append(NSAttributedString(string: prefix, attributes: prefixAttrs))
            }
            if components.contains(where: { if case .thematicBreak = $0.kind { return true }; return false }) {
                out.append(NSAttributedString(string: "────────", attributes: attributes))
            } else {
                out.append(NSAttributedString(string: text, attributes: attributes))
            }

            lastBlock = block
            lastListItem = listItem
            lastRow = row
        }
        return out
    }

    private static func bodyAttributes() -> [NSAttributedString.Key: Any] {
        [
            .font: Theme.Typography.ui(Theme.TypeScale.current),
            .foregroundColor: Theme.Editor.text,
        ]
    }

    private static func mutedMono() -> [NSAttributedString.Key: Any] {
        [
            .font: Theme.Typography.mono(Theme.TypeScale.current - 1),
            .foregroundColor: Theme.chromeMutedText,
        ]
    }

    private static func headingFont(_ level: Int) -> NSFont {
        let base = Theme.TypeScale.current
        switch level {
        case 1: return Theme.Typography.ui(base * 1.7, weight: .bold)
        case 2: return Theme.Typography.ui(base * 1.4, weight: .semibold)
        case 3: return Theme.Typography.ui(base * 1.2, weight: .semibold)
        default: return Theme.Typography.ui(base * 1.05, weight: .semibold)
        }
    }

    private static func boldened(_ font: NSFont?) -> NSFont {
        let font = font ?? Theme.Typography.ui(Theme.TypeScale.current)
        return NSFontManager.shared.convert(font, toHaveTrait: .boldFontMask)
    }
}
