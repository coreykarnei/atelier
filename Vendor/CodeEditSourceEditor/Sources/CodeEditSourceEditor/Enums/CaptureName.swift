//
//  CaptureNames.swift
//  CodeEditSourceEditor
//
//  Created by Lukas Pistrol on 16.08.22.
//

/// A collection of possible syntax capture types. Represented by an integer for memory efficiency, and with the
/// ability to convert to and from strings for ease of use with tools.
///
/// This is `Int8` raw representable for memory considerations. In large documents there can be *lots* of these created
/// and passed around, so representing them with a single integer is preferable to a string to save memory.
///
public enum CaptureName: Int8, CaseIterable, Sendable {
    case include
    case constructor
    case keyword
    case boolean
    case `repeat`
    case conditional
    case tag
    case comment
    case variable
    case property
    case function
    case method
    case number
    case float
    case string
    case type
    case parameter
    case typeAlternate
    case variableBuiltin
    case keywordReturn
    case keywordFunction
    // Atelier patch: captures the bundled queries emit that had no case, so
    // they fell to plain text (function.builtin, constant, operator…).
    case functionBuiltin
    case constant
    case constantBuiltin
    case `operator`
    case punctuation
    case escape
    case typeBuiltin
    case attribute
    case namespace
    case label
    // Atelier patch: markup captures for prose grammars (markdown): headings,
    // emphasis, raw code, links, list markers, quotes. Aliased from nvim's
    // `markup.*` names and the older `text.*` names in `fromString`.
    case markupHeading1
    case markupHeading
    case markupStrong
    case markupItalic
    case markupStrikethrough
    case markupRaw
    case markupLink
    case markupUrl
    case markupList
    case markupQuote

    var alternate: CaptureName {
        switch self {
        case .type:
            return .typeAlternate
        default:
            return self
        }
    }

    /// Returns a specific capture name case from a given string.
    /// - Note: See ``CaptureName`` docs for why this enum isn't a raw representable.
    /// - Parameter string: A string to get the capture name from
    /// - Returns: A `CaptureNames` case
    public static func fromString(_ string: String?) -> CaptureName? { // swiftlint:disable:this cyclomatic_complexity function_body_length
        guard let string else { return nil }
        switch string {
        case "include":
            return .include
        case "constructor":
            return .constructor
        case "keyword":
            return .keyword
        case "boolean":
            return .boolean
        case "repeat":
            return .repeat
        case "conditional":
            return .conditional
        case "tag":
            return .tag
        case "comment":
            return .comment
        case "variable":
            return .variable
        case "property":
            return .property
        case "function":
            return .function
        case "method":
            return .method
        case "number":
            return .number
        case "float":
            return .float
        case "string":
            return .string
        case "type":
            return .type
        case "parameter":
            return .parameter
        case "type_alternate":
            return .typeAlternate
        case "variable.builtin":
            return .variableBuiltin
        case "keyword.return":
            return .keywordReturn
        case "keyword.function":
            return .keywordFunction
        case "function.builtin": return .functionBuiltin
        case "function.method", "function.method.call", "method.call": return .method
        case "function.call", "function.macro": return .function
        case "variable.parameter": return .parameter
        case "variable.member", "field": return .property
        case "constant": return .constant
        case "constant.builtin", "constant.macro": return .constantBuiltin
        case "operator", "keyword.operator": return .operator
        case "punctuation", "punctuation.bracket", "punctuation.delimiter", "punctuation.special": return .punctuation
        case "escape", "string.escape": return .escape
        case "string.special", "string.regex", "string.special.symbol", "character": return .string
        case "type.builtin", "type.qualifier": return .typeBuiltin
        case "type.definition": return .type  // a declared type's name paints like its uses
        case "keyword.conditional.ternary": return .operator
        case "attribute", "annotation", "decorator": return .attribute
        case "namespace", "module": return .namespace
        case "label": return .label
        case "keyword.import", "keyword.include": return .include
        case "keyword.conditional", "keyword.exception": return .conditional
        case "keyword.repeat": return .repeat
        case "keyword.type", "keyword.modifier", "keyword.storage", "keyword.coroutine": return .keyword
        case "comment.documentation", "spell": return .comment
        case "number.float": return .float
        // Markup (markdown): nvim `markup.*` and the older `text.*` names.
        case "markup.heading.1", "text.title.1": return .markupHeading1
        case "markup.heading", "markup.heading.2", "markup.heading.3", "markup.heading.4",
             "markup.heading.5", "markup.heading.6", "markup.heading.marker", "text.title": return .markupHeading
        case "markup.strong", "markup.bold", "text.strong": return .markupStrong
        case "markup.italic", "markup.emphasis", "text.emphasis": return .markupItalic
        case "markup.strikethrough", "text.strike": return .markupStrikethrough
        case "markup.raw", "markup.raw.block", "markup.raw.inline", "text.literal": return .markupRaw
        case "markup.link", "markup.link.label", "markup.link.text", "text.reference": return .markupLink
        case "markup.link.url", "text.uri": return .markupUrl
        case "markup.list", "markup.list.checked", "markup.list.unchecked",
             "markup.list.numbered", "markup.list.unnumbered": return .markupList
        case "markup.quote": return .markupQuote
        default:
            // Unknown dotted capture: fall back to its head ("string.foo" → string).
            if let dot = string.firstIndex(of: "."), dot > string.startIndex {
                return fromString(String(string[..<dot]))
            }
            return nil
        }
    }

    /// See ``CaptureName`` docs for why this enum isn't a raw representable.
    var stringValue: String {
        switch self {
        case .include:
            return "include"
        case .constructor:
            return "constructor"
        case .keyword:
            return "keyword"
        case .boolean:
            return "boolean"
        case .repeat:
            return "`repeat`"
        case .conditional:
            return "conditional"
        case .tag:
            return "tag"
        case .comment:
            return "comment"
        case .variable:
            return "variable"
        case .property:
            return "property"
        case .function:
            return "function"
        case .method:
            return "method"
        case .number:
            return "number"
        case .float:
            return "float"
        case .string:
            return "string"
        case .type:
            return "type"
        case .parameter:
            return "parameter"
        case .typeAlternate:
            return "typeAlternate"
        case .variableBuiltin:
            return "variableBuiltin"
        case .keywordReturn:
            return "keywordReturn"
        case .keywordFunction:
            return "keywordFunction"
        case .functionBuiltin: return "function.builtin"
        case .constant: return "constant"
        case .constantBuiltin: return "constant.builtin"
        case .operator: return "operator"
        case .punctuation: return "punctuation"
        case .escape: return "escape"
        case .typeBuiltin: return "type.builtin"
        case .attribute: return "attribute"
        case .namespace: return "namespace"
        case .label: return "label"
        case .markupHeading1: return "markup.heading.1"
        case .markupHeading: return "markup.heading"
        case .markupStrong: return "markup.strong"
        case .markupItalic: return "markup.italic"
        case .markupStrikethrough: return "markup.strikethrough"
        case .markupRaw: return "markup.raw"
        case .markupLink: return "markup.link"
        case .markupUrl: return "markup.link.url"
        case .markupList: return "markup.list"
        case .markupQuote: return "markup.quote"
        }
    }
}

extension CaptureName: CustomDebugStringConvertible {
    public var debugDescription: String { stringValue }
}
