//
//  RowRenderCache.swift
//
//  Atelier patch: remembers each drawn row's shaped text so a redraw of an
//  unchanged row skips building its attributed string, CoreText shaping and
//  the per-run attribute bridging — the bulk of a CPU draw. Rows are keyed by
//  content, not position, so a row that only moved (scrollback, a TUI
//  repainting shifted lines) is still a hit.
//
#if os(macOS) || os(iOS) || os(visionOS)
import Foundation
import CoreGraphics
import CoreText

/// One glyph run of a row, with everything the draw loops read from it.
struct PreparedRun {
    /// First column of the run, and columns per glyph.
    let startColumn: Int
    let columnWidth: Int
    let glyphs: [CGGlyph]
    /// CoreText's positions; only `y` is used — `x` comes from the cell grid.
    let glyphYOffsets: [CGFloat]
    let font: TTFont
    let foreground: TTColor?
    /// The selection colour when selected, else the cell background.
    let background: TTColor?
    /// For `drawRunAttributes` (underline, strikethrough).
    let attributes: [NSAttributedString.Key: Any]
    let endColumn: Int
}

/// A row ready to draw: the build output plus its shaped runs.
final class PreparedRow {
    let lineInfo: ViewLineInfo
    let runs: [PreparedRun]
    fileprivate let key: RowRenderCache.Key
    fileprivate let cells: [UInt8]
    fileprivate var lastUsed: Int

    fileprivate init(lineInfo: ViewLineInfo, runs: [PreparedRun], key: RowRenderCache.Key, cells: [UInt8], lastUsed: Int) {
        self.lineInfo = lineInfo
        self.runs = runs
        self.key = key
        self.cells = cells
        self.lastUsed = lastUsed
    }

    /// Shapes `lineInfo`'s segments and lifts out what drawing needs.
    static func runs(for lineInfo: ViewLineInfo) -> [PreparedRun] {
        var result: [PreparedRun] = []
        for segment in lineInfo.segments where segment.attributedString.length > 0 {
            let ctLine = CTLineCreateWithAttributedString(segment.attributedString)
            guard let runs = CTLineGetGlyphRuns(ctLine) as? [CTRun] else { continue }
            var processedGlyphs = 0
            for run in runs {
                let count = CTRunGetGlyphCount(run)
                if count == 0 { continue }
                let attributes = CTRunGetAttributes(run) as? [NSAttributedString.Key: Any] ?? [:]
                let glyphs = [CGGlyph](unsafeUninitializedCapacity: count) { buffer, initialized in
                    CTRunGetGlyphs(run, CFRange(), buffer.baseAddress!)
                    initialized = count
                }
                var positions = [CGPoint](repeating: .zero, count: count)
                CTRunGetPositions(run, CFRange(), &positions)
                let background = (attributes[.selectionBackgroundColor] ?? attributes[.backgroundColor]) as? TTColor
                let startColumn = segment.column + processedGlyphs * segment.columnWidth
                result.append(PreparedRun(startColumn: startColumn,
                                          columnWidth: segment.columnWidth,
                                          glyphs: glyphs,
                                          glyphYOffsets: positions.map(\.y),
                                          font: attributes[.font] as! TTFont,
                                          foreground: attributes[.foregroundColor] as? TTColor,
                                          background: background,
                                          attributes: attributes,
                                          endColumn: startColumn + count * segment.columnWidth))
                processedGlyphs += count
            }
        }
        return result
    }
}

/// Content-keyed store of `PreparedRow`s. A hit requires the row's cells to
/// be byte-identical. Equal bytes are equal cells (and grapheme-cluster codes
/// are never reused), so a hit can never draw stale text; equal cells whose
/// unused enum payload bytes differ only cost a miss — measured cheaper than
/// canonicalising every cell on every draw. Everything else the
/// build reads that isn't in the cells is part of the key; view-wide inputs
/// (fonts, palette, selection colour) clear the store instead.
public final class RowRenderCache {
    /// Everything but the cells.
    struct Key: Equatable {
        var cols: Int
        var selection: Range<Int>?
        var linkHover: Range<Int>?
        var linkModifier: Bool
        var brightColors: Bool
        var customGlyphs: Bool
    }

    private var rows: [Int: [PreparedRow]] = [:]
    private var count = 0
    private var draw = 0
    /// Hosts may switch the cache off (A/B measurement); on by default.
    nonisolated(unsafe) public static var isEnabled = true
    /// Lookups since the host last zeroed them (measurement only).
    nonisolated(unsafe) public static var hits = 0
    nonisolated(unsafe) public static var misses = 0

    /// Call once per draw; ages out rows unused for a few draws once the
    /// store outgrows `limit`.
    func beginDraw(limit: Int) {
        draw += 1
        guard count > limit else { return }
        let horizon = draw - 4
        for (hash, bucket) in rows {
            let kept = bucket.filter { $0.lastUsed >= horizon }
            count -= bucket.count - kept.count
            rows[hash] = kept.isEmpty ? nil : kept
        }
    }

    func removeAll() {
        rows = [:]
        count = 0
    }

    /// Looks up a row by key and cell bytes; returns its hash too, for `insert`.
    func row(for key: Key, cells: UnsafeRawBufferPointer) -> (PreparedRow?, Int) {
        var hasher = Hasher()
        hasher.combine(bytes: cells)
        hasher.combine(key.cols)
        hasher.combine(key.selection?.lowerBound)
        hasher.combine(key.selection?.upperBound)
        hasher.combine(key.linkHover?.lowerBound)
        hasher.combine(key.linkHover?.upperBound)
        let hash = hasher.finalize()
        guard let hit = rows[hash]?.first(where: { row in
            row.key == key && row.cells.count == cells.count
                && row.cells.withUnsafeBytes { memcmp($0.baseAddress!, cells.baseAddress!, cells.count) == 0 }
        }) else {
            RowRenderCache.misses += 1
            return (nil, hash)
        }
        RowRenderCache.hits += 1
        hit.lastUsed = draw
        return (hit, hash)
    }

    func insert(key: Key, cells: UnsafeRawBufferPointer, hash: Int, lineInfo: ViewLineInfo, runs: [PreparedRun]) {
        let row = PreparedRow(lineInfo: lineInfo, runs: runs, key: key, cells: Array(cells), lastUsed: draw)
        rows[hash, default: []].append(row)
        count += 1
    }
}
#endif
