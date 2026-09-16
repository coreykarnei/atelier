//
//  EditorTheme.swift
//  CodeEditSourceEditor
//
//  Created by Lukas Pistrol on 29.05.22.
//

import SwiftUI

/// A collection of attributes used for syntax highlighting and other colors for the editor.
///
/// Attributes of a theme that do not apply to text (background, line highlight) are a single `NSColor` for simplicity.
/// All other attributes use the ``EditorTheme/Attribute`` type to store
public struct EditorTheme: Equatable {
    /// Represents attributes that can be applied to style text.
    public struct Attribute: Equatable, Hashable, Sendable {
        public let color: NSColor
        public let bold: Bool
        public let italic: Bool

        public init(color: NSColor, bold: Bool = false, italic: Bool = false) {
            self.color = color
            self.bold = bold
            self.italic = italic
        }
    }

    public var text: Attribute
    public var insertionPoint: NSColor
    public var invisibles: Attribute
    public var background: NSColor
    public var lineHighlight: NSColor
    public var selection: NSColor
    public var keywords: Attribute
    public var commands: Attribute
    public var types: Attribute
    public var attributes: Attribute
    public var variables: Attribute
    public var values: Attribute
    public var numbers: Attribute
    public var strings: Attribute
    public var characters: Attribute
    public var comments: Attribute
    /// Atelier patch: attributes per capture, consulted before the coarse
    /// slot mapping below. Lets a theme colour functions, properties,
    /// parameters, builtins… apart instead of collapsing them into
    /// `variables`/`keywords`.
    public var captures: [CaptureName: Attribute]

    public init(
        text: Attribute,
        insertionPoint: NSColor,
        invisibles: Attribute,
        background: NSColor,
        lineHighlight: NSColor,
        selection: NSColor,
        keywords: Attribute,
        commands: Attribute,
        types: Attribute,
        attributes: Attribute,
        variables: Attribute,
        values: Attribute,
        numbers: Attribute,
        strings: Attribute,
        characters: Attribute,
        comments: Attribute,
        captures: [CaptureName: Attribute] = [:]
    ) {
        self.text = text
        self.insertionPoint = insertionPoint
        self.invisibles = invisibles
        self.background = background
        self.lineHighlight = lineHighlight
        self.selection = selection
        self.keywords = keywords
        self.commands = commands
        self.types = types
        self.attributes = attributes
        self.variables = variables
        self.values = values
        self.numbers = numbers
        self.strings = strings
        self.characters = characters
        self.comments = comments
        self.captures = captures
    }

    /// Maps a capture type to the attributes for that capture determined by the theme.
    /// - Parameter capture: The capture to map to.
    /// - Returns: Theme attributes for the capture.
    private func mapCapture(_ capture: CaptureName?) -> Attribute {
        if let capture, let exact = captures[capture] { return exact }
        if let capture, let markup = markupFallback(capture) { return markup }
        switch capture {
        case .include, .constructor, .keyword, .boolean, .variableBuiltin,
                .keywordReturn, .keywordFunction, .repeat, .conditional, .tag:
            return keywords
        case .comment: return comments
        case .variable, .property: return variables
        case .function, .method: return variables
        case .number, .float: return numbers
        case .string: return strings
        case .type: return types
        case .parameter: return variables
        case .typeAlternate: return attributes
        case .functionBuiltin: return variables
        case .constant, .constantBuiltin: return values
        case .typeBuiltin: return types
        case .attribute: return attributes
        case .namespace, .label: return types
        case .operator, .punctuation, .escape: return text
        default: return text
        }
    }

    /// Atelier patch: markup (markdown) fallbacks for themes that don't set
    /// them per capture — headings borrow the keyword colour in bold,
    /// strong/italic are the text colour with the trait, raw code reads as a
    /// string, links as types, list markers and quotes as comments.
    private func markupFallback(_ capture: CaptureName) -> Attribute? {
        switch capture {
        case .markupHeading1, .markupHeading: return Attribute(color: keywords.color, bold: true)
        case .markupStrong: return Attribute(color: text.color, bold: true)
        case .markupItalic: return Attribute(color: text.color, italic: true)
        case .markupStrikethrough: return comments
        case .markupRaw: return strings
        case .markupLink, .markupUrl: return types
        case .markupList, .markupQuote: return comments
        default: return nil
        }
    }

    /// Get the color from ``theme`` for the specified capture name.
    /// - Parameter capture: The capture name
    /// - Returns: A `NSColor`
    func colorFor(_ capture: CaptureName?) -> NSColor {
        return mapCapture(capture).color
    }

    /// Returns the correct font with attributes (bold and italics) for a given capture name.
    /// - Parameters:
    ///   - capture: The capture name.
    ///   - font: The font to add attributes to.
    /// - Returns: A new font that has the correct attributes for the capture.
    func fontFor(for capture: CaptureName?, from font: NSFont) -> NSFont {
        let attributes = mapCapture(capture)
        guard attributes.bold || attributes.italic else {
            return font
        }

        var font = font

        if attributes.bold {
            font = NSFontManager.shared.convert(font, toHaveTrait: .boldFontMask)
        }

        if attributes.italic {
            font = NSFontManager.shared.convert(font, toHaveTrait: .italicFontMask)
        }

        return font
    }
}
