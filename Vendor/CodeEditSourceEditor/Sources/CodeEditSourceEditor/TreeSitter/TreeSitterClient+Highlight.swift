//
//  TreeSitterClient+Highlight.swift
//  CodeEditSourceEditor
//
//  Created by Khan Winter on 3/10/23.
//

import Foundation
import SwiftTreeSitter
import CodeEditLanguages

extension TreeSitterClient {
    func queryHighlightsForRange(range: NSRange) -> [HighlightRange] {
        guard let state = self.state else { return [] }

        var highlights: [HighlightRange] = []
        var injectedSet = IndexSet(integersIn: range)

        for layer in state.layers where layer.id != state.primaryLayer.id {
            // Query injected only if a layer's ranges intersects with `range`
            for layerRange in layer.ranges {
                if let rangeIntersection = range.intersection(layerRange) {
                    let queryResult = queryLayerHighlights(
                        layer: layer,
                        range: rangeIntersection
                    )

                    highlights.append(contentsOf: queryResult)
                    injectedSet.remove(integersIn: rangeIntersection)
                }
            }
        }

        // Query primary for any ranges that weren't used in the injected layers.
        for range in injectedSet.rangeView {
            let queryResult = queryLayerHighlights(
                layer: state.layers[0],
                range: NSRange(range)
            )
            highlights.append(contentsOf: queryResult)
        }

        return highlights
    }

    /// Queries the given language layer for any highlights.
    /// - Parameters:
    ///   - layer: The layer to query.
    ///   - range: The range to query for.
    /// - Returns: Any ranges to highlight.
    internal func queryLayerHighlights(
        layer: LanguageLayer,
        range: NSRange
    ) -> [HighlightRange] {
        guard let tree = layer.tree,
              let rootNode = tree.rootNode else {
            return []
        }

        // This needs to be on the main thread since we're going to use the `textProvider` in
        // the `highlightsFromCursor` method, which uses the textView's text storage.
        guard let queryCursor = layer.languageQuery?.execute(node: rootNode, in: tree) else {
            return []
        }
        queryCursor.setRange(range)
        queryCursor.matchLimit =  Constants.matchLimit

        var highlights: [HighlightRange] = []

        // See https://github.com/CodeEditApp/CodeEditSourceEditor/pull/228
        if layer.id == .jsdoc {
            highlights.append(HighlightRange(range: range, capture: .comment))
        }

        highlights += highlightsFromCursor(cursor: queryCursor, includedRange: range)

        return highlights
    }

    /// Resolves a query cursor to the highlight ranges it contains.
    /// **Must be called on the main thread**
    /// - Parameters:
    ///     - cursor: The cursor to resolve.
    ///     - includedRange: The range to include highlights from.
    /// - Returns: Any highlight ranges contained in the cursor.
    internal func highlightsFromCursor(
        cursor: QueryCursor,
        includedRange: NSRange
    ) -> [HighlightRange] {
        guard let readCallback else { return [] }
        // Atelier patch: one winner per range. The old pass filtered a
        // later capture only if a *lower*-indexed one had already been seen
        // for that range — so when the generic capture (`(identifier)
        // @variable`) was encountered first it was emitted *and* the
        // specific one (`@function`) was emitted after it. The style
        // container then keeps the first of two runs at the same location
        // and drops the second: every function name in Python rendered as
        // a variable. Keep the lowest-indexed (earliest-in-query) capture
        // per range, then emit in document order.
        var best: [NSRange: (index: Int, capture: CaptureName)] = [:]
        for capture in cursor.resolve(with: .init(textProvider: readCallback)).flatMap({ $0.captures }) {
            guard let captureName = CaptureName.fromString(capture.name) else { continue }
            let range = capture.range
            if let existing = best[range], existing.index <= capture.index { continue }
            best[range] = (capture.index, captureName)
        }
        return best.compactMap { range, value -> HighlightRange? in
            guard let intersection = range.intersection(includedRange), intersection.length > 0 else { return nil }
            return HighlightRange(range: intersection, capture: value.capture)
        }.sorted { lhs, rhs in
            lhs.range.location != rhs.range.location
                ? lhs.range.location < rhs.range.location
                : lhs.range.length > rhs.range.length
        }
    }
}
