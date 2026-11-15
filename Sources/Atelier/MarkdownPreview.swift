import AppKit

/// Rendered markdown for the editor's Preview mode (M2.6). Foundation parses
/// (`AttributedString(markdown:)`, full syntax — headings, lists, quotes,
/// code blocks, tables, links); this view lays the blocks out and dresses
/// them in Mocha: two-voice type (ui for prose, mono for code), the
/// content type scale, translucent like the buffer it stands in for.
/// Read-only and selectable; copy gives you the rendered text.
///
/// Images (2026-11-15, owner report: a README's `<img>` showed as its own
/// source): Markdown images and the HTML ones READMEs lean on are drawn
/// when they are files inside the folder being worked in, fitted to the
/// column. One that lives on the network is never fetched — opening a
/// folder must not phone anyone — and shows its alt text, muted, in its
/// place. `MarkdownSource` also folds the small set of HTML tags READMEs
/// use for layout (`<a>`, `<p align>`, `<picture>`, `<br>`, `<b>`…) into
/// Markdown, since Foundation's parser hands raw HTML back as text.
final class MarkdownPreviewView: NSView {
    private let scroll = NSScrollView()
    private let textView = NSTextView()

    /// Where the document's relative image paths start: its own directory.
    var baseDirectory: String?
    /// The folder images may be read from (the session's root); nothing
    /// outside it is opened, whatever a path or a symlink says.
    var imageRoot: String?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor // the pane washes the region once (see EditorPane)

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

        textView.delegate = self
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
        layer?.backgroundColor = NSColor.clear.cgColor // the pane washes the region once (see EditorPane)
    }

    /// A document just opened starts at its top — and stays there through
    /// the first real layout: a session's default file is rendered before
    /// its pane has a size, and the reflow that follows (the column widens,
    /// the pictures grow into it) otherwise left the view part-way down.
    func scrollToTop() {
        pinnedToTop = true
        pinTop()
    }

    private var pinnedToTop = false

    private func pinTop() {
        scroll.contentView.scroll(to: .zero)
        scroll.reflectScrolledClipView(scroll.contentView)
    }

    override func layout() {
        super.layout()
        guard pinnedToTop, window != nil, bounds.width > 1, bounds.height > 1 else { return }
        if let container = textView.textContainer { textView.layoutManager?.ensureLayout(for: container) }
        pinTop()
        // Once more after this pass settles, then the position is yours.
        DispatchQueue.main.async { [weak self] in
            guard let self, self.pinnedToTop else { return }
            self.pinTop()
            self.pinnedToTop = false
        }
    }

    /// Replace the rendering, keeping the scroll position when the document
    /// merely changed under you (live preview while typing).
    func render(markdown: String) {
        let origin = scroll.contentView.bounds.origin
        let images = ImageResolver(baseDirectory: baseDirectory, root: imageRoot)
        textView.textStorage?.setAttributedString(Self.render(markdown, images: images))
        textView.layoutManager?.ensureLayout(for: textView.textContainer!)
        scroll.contentView.scroll(to: origin)
        scroll.reflectScrolledClipView(scroll.contentView)
    }

    // MARK: Rendering

    private static func render(_ markdown: String, images: ImageResolver) -> NSAttributedString {
        let source = MarkdownSource(markdown)
        let markdown = source.text
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
                // Text, with each image the source set aside put back where
                // its marker stands — drawn, or named by its alt text.
                for piece in source.pieces(of: text) {
                    switch piece {
                    case .text(let string):
                        out.append(NSAttributedString(string: string, attributes: attributes))
                    case .image(let image):
                        out.append(images.rendering(of: image, attributes: attributes))
                    }
                }
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

// MARK: - Source

/// A Markdown document made ready for Foundation's parser: images set aside
/// behind markers (the parser drops an image's address once it sits inside
/// a link, and never sees an HTML `<img>` at all), and the layout HTML of
/// READMEs folded into Markdown. Code — fenced blocks and inline spans — is
/// left exactly as written.
struct MarkdownSource {
    struct Image {
        let source: String
        let alt: String
        /// Points, from a `width="128"`; nil for none or a percentage.
        let width: CGFloat?
    }

    enum Piece {
        case text(String)
        case image(Image)
    }

    private(set) var text: String
    private var images: [Image] = []

    // Private-use scalars: they mean nothing to Markdown and are in no README.
    private static let imageOpen: Character = "\u{E000}", imageClose: Character = "\u{E001}"
    private static let codeOpen: Character = "\u{E002}", codeClose: Character = "\u{E003}"

    init(_ markdown: String) {
        text = markdown
        // Code first, out of reach of everything below.
        var code: [String] = []
        func shelve(_ pattern: String, options: NSRegularExpression.Options = []) {
            text = Self.replace(pattern, in: text, options: options) { match, _ in
                code.append(match[0])
                return "\(Self.codeOpen)\(code.count - 1)\(Self.codeClose)"
            }
        }
        shelve("^ {0,3}(```|~~~)[^\\n]*\\n[\\s\\S]*?(?:^ {0,3}\\1[^\\n]*$|\\z)", options: [.anchorsMatchLines])
        shelve("(`+)[^`\\n][^\\n]*?\\1")

        text = Self.replace("<!--[\\s\\S]*?-->", in: text) { _, _ in "" }
        // Images: HTML, then Markdown's own.
        var found: [Image] = []
        func marker(_ image: Image) -> String {
            found.append(image)
            return "\(Self.imageOpen)\(found.count - 1)\(Self.imageClose)"
        }
        text = Self.replace("<img\\b[^>]*>", in: text, options: [.caseInsensitive]) { match, _ in
            guard let source = Self.attribute("src", in: match[0]), !source.isEmpty else { return "" }
            let width = Self.attribute("width", in: match[0]).flatMap { $0.hasSuffix("%") ? nil : Double($0.replacingOccurrences(of: "px", with: "")) }
            return marker(Image(source: source, alt: Self.attribute("alt", in: match[0]) ?? "", width: width.map { CGFloat($0) }))
        }
        text = Self.replace("!\\[([^\\]]*)\\]\\(\\s*<?([^)\\s>]+)>?(?:\\s+\"[^\"]*\")?\\s*\\)", in: text) { match, _ in
            marker(Image(source: match[2], alt: match[1], width: nil))
        }
        images = found

        // The HTML READMEs use for layout, as the Markdown it stands for.
        text = Self.replace("<a\\b[^>]*>([\\s\\S]*?)</a>", in: text, options: [.caseInsensitive]) { match, _ in
            let inner = match[1].trimmingCharacters(in: .whitespacesAndNewlines)
            guard let href = Self.attribute("href", in: match[0]), !href.isEmpty, !inner.isEmpty else { return inner }
            return "[\(inner)](\(href))"
        }
        text = Self.replace("<h([1-6])\\b[^>]*>([\\s\\S]*?)</h\\1>", in: text, options: [.caseInsensitive]) { match, _ in
            "\n" + String(repeating: "#", count: Int(match[1]) ?? 1) + " "
                + match[2].trimmingCharacters(in: .whitespacesAndNewlines) + "\n"
        }
        for (pattern, replacement) in [
            ("<br\\s*/?>", "  \n"),
            ("</?(?:b|strong)\\b[^>]*>", "**"),
            ("</?(?:i|em)\\b[^>]*>", "*"),
            ("</?(?:code|kbd)\\b[^>]*>", "`"),
            ("</(?:p|div|center|details|summary|figure|figcaption)>", "\n"),
            ("</?(?:p|div|center|details|summary|figure|figcaption|picture|source|span|sub|sup|small)\\b[^>]*>", ""),
        ] {
            text = Self.replace(pattern, in: text, options: [.caseInsensitive]) { _, _ in replacement }
        }

        text = Self.replace("\(Self.codeOpen)(\\d+)\(Self.codeClose)", in: text) { match, _ in
            Int(match[1]).flatMap { code.indices.contains($0) ? code[$0] : nil } ?? ""
        }
    }

    /// A run of parsed text, split at the image markers it carries.
    func pieces(of string: String) -> [Piece] {
        guard string.contains(Self.imageOpen) else { return [.text(string)] }
        var pieces: [Piece] = []
        var rest = Substring(string)
        while let open = rest.firstIndex(of: Self.imageOpen),
              let close = rest[open...].firstIndex(of: Self.imageClose) {
            if open > rest.startIndex { pieces.append(.text(String(rest[..<open]))) }
            if let index = Int(rest[rest.index(after: open)..<close]), images.indices.contains(index) {
                pieces.append(.image(images[index]))
            }
            rest = rest[rest.index(after: close)...]
        }
        if !rest.isEmpty { pieces.append(.text(String(rest))) }
        return pieces
    }

    /// `name="value"` (or single-quoted, or bare) out of one HTML tag.
    private static func attribute(_ name: String, in tag: String) -> String? {
        let pattern = "\\b\(name)\\s*=\\s*(?:\"([^\"]*)\"|'([^']*)'|([^\\s>]+))"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
              let match = regex.firstMatch(in: tag, range: NSRange(tag.startIndex..., in: tag)) else { return nil }
        for group in 1...3 {
            if let range = Range(match.range(at: group), in: tag) { return String(tag[range]) }
        }
        return nil
    }

    /// Every match of `pattern` replaced by what `transform` returns for
    /// its capture groups (group 0 is the whole match; a group that took
    /// no part is "").
    private static func replace(
        _ pattern: String, in string: String, options: NSRegularExpression.Options = [],
        _ transform: (_ groups: [String], _ range: NSRange) -> String
    ) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: options) else { return string }
        let source = string as NSString
        var out = ""
        var cursor = 0
        for match in regex.matches(in: string, range: NSRange(location: 0, length: source.length)) {
            out += source.substring(with: NSRange(location: cursor, length: match.range.location - cursor))
            let groups = (0..<match.numberOfRanges).map { index -> String in
                let range = match.range(at: index)
                return range.location == NSNotFound ? "" : source.substring(with: range)
            }
            out += transform(groups, match.range)
            cursor = match.range.location + match.range.length
        }
        return out + source.substring(from: cursor)
    }
}

// MARK: - Images

/// Finds the file an image names and draws it — if it is a file in the
/// folder. Decoded images are kept by path and modification date, since
/// the preview re-renders as you type.
struct ImageResolver {
    let baseDirectory: String?
    let root: String?

    private static let cache = NSCache<NSString, NSImage>()
    /// Nothing larger is decoded on the main thread for a preview.
    private static let byteLimit = 30_000_000

    /// The attachment for a local image, or its alt text, muted — linking
    /// to the address when that is on the network and nothing else already
    /// links there.
    func rendering(of image: MarkdownSource.Image, attributes: [NSAttributedString.Key: Any]) -> NSAttributedString {
        if let loaded = load(image.source) {
            let attachment = FittedImageAttachment()
            attachment.image = loaded
            attachment.preferredWidth = image.width
            let string = NSMutableAttributedString(attachment: attachment)
            var carried: [NSAttributedString.Key: Any] = [:]
            for key in [NSAttributedString.Key.link, .paragraphStyle] { carried[key] = attributes[key] }
            string.addAttributes(carried, range: NSRange(location: 0, length: string.length))
            return string
        }
        var muted = attributes
        muted[.foregroundColor] = Theme.chromeMutedText
        muted[.backgroundColor] = nil
        if muted[.link] == nil, let url = URL(string: image.source), ["http", "https"].contains(url.scheme?.lowercased() ?? "") {
            muted[.link] = url
        }
        let name = image.alt.trimmingCharacters(in: .whitespacesAndNewlines)
        return NSAttributedString(string: name.isEmpty ? "[image]" : "[\(name)]", attributes: muted)
    }

    private func load(_ source: String) -> NSImage? {
        guard let path = localPath(source) else { return nil }
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: path),
              attributes[.type] as? FileAttributeType == .typeRegular,
              let size = attributes[.size] as? Int, size > 0, size <= Self.byteLimit else { return nil }
        let stamp = (attributes[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0
        let key = "\(path)|\(stamp)|\(size)" as NSString
        if let cached = Self.cache.object(forKey: key) { return cached }
        guard let image = NSImage(contentsOfFile: path), image.isValid, image.size.width > 0, image.size.height > 0 else {
            return nil
        }
        Self.cache.setObject(image, forKey: key)
        return image
    }

    /// The file `source` names, when it is one inside the folder: relative
    /// to the document, or — with a leading slash, as on GitHub — to the
    /// root. Anything with a scheme is somewhere else.
    private func localPath(_ source: String) -> String? {
        guard let baseDirectory else { return nil }
        var name = source
        if let cut = name.firstIndex(where: { $0 == "?" || $0 == "#" }) { name = String(name[..<cut]) }
        guard !name.isEmpty, name.range(of: "^[A-Za-z][A-Za-z0-9+.-]*:", options: .regularExpression) == nil,
              !name.hasPrefix("//") else { return nil }
        name = name.removingPercentEncoding ?? name
        let folder = root ?? baseDirectory
        let joined = name.hasPrefix("/")
            ? (folder as NSString).appendingPathComponent(name)
            : (baseDirectory as NSString).appendingPathComponent(name)
        let resolved = URL(fileURLWithPath: joined).resolvingSymlinksInPath().path
        let home = URL(fileURLWithPath: folder).resolvingSymlinksInPath().path
        guard resolved.hasPrefix(home.hasSuffix("/") ? home : home + "/") else { return nil }
        return resolved
    }
}

/// An image that never outgrows its line: its own size (or the width its
/// tag asked for), scaled down to the column when that is narrower — asked
/// at layout, so the picture follows the pane as it is resized.
final class FittedImageAttachment: NSTextAttachment {
    var preferredWidth: CGFloat?

    override func attachmentBounds(
        for textContainer: NSTextContainer?, proposedLineFragment lineFrag: NSRect,
        glyphPosition position: NSPoint, characterIndex charIndex: Int
    ) -> NSRect {
        guard let image, image.size.width > 0 else { return .zero }
        let room = max(40, lineFrag.width - 2 * (textContainer?.lineFragmentPadding ?? 0))
        let width = min(preferredWidth ?? image.size.width, room)
        return NSRect(x: 0, y: 0, width: width, height: (width * image.size.height / image.size.width).rounded())
    }
}

extension MarkdownPreviewView: NSTextViewDelegate {
    /// A rendered link opens the way a terminal link does — through
    /// `LinkPolicy`, which asks before anything that runs. One without a
    /// scheme (a repo-relative `docs/x.md`) names nothing this view can
    /// resolve and is left alone.
    func textView(_ textView: NSTextView, clickedOnLink link: Any, at charIndex: Int) -> Bool {
        let url = (link as? URL) ?? (link as? String).flatMap(URL.init(string:))
        guard let url, url.scheme != nil else { return true }
        let target = url.isFileURL ? URL(fileURLWithPath: url.path) : url
        LinkPolicy.open(target, from: self) { NSWorkspace.shared.open(target) }
        return true
    }
}
