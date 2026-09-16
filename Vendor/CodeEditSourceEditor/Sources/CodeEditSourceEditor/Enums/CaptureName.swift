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
    public static func fromString(_ string: String?) -> CaptureName? { // swiftlint:disable:this cyclomatic_complexity
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
        case "function.method", "method.call": return .method
        case "function.call", "function.macro": return .function
        case "variable.parameter": return .parameter
        case "variable.member", "field": return .property
        case "constant": return .constant
        case "constant.builtin", "constant.macro": return .constantBuiltin
        case "operator", "keyword.operator": return .operator
        case "punctuation", "punctuation.bracket", "punctuation.delimiter", "punctuation.special": return .punctuation
        case "escape", "string.escape": return .escape
        case "string.special", "string.regex", "string.special.symbol", "character": return .string
        case "type.builtin", "type.definition", "type.qualifier": return .typeBuiltin
        case "attribute", "annotation", "decorator": return .attribute
        case "namespace", "module": return .namespace
        case "label": return .label
        case "keyword.import", "keyword.include": return .include
        case "keyword.conditional", "keyword.exception": return .conditional
        case "keyword.repeat": return .repeat
        case "keyword.type", "keyword.modifier", "keyword.storage", "keyword.coroutine": return .keyword
        case "comment.documentation", "spell": return .comment
        case "number.float": return .float
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
        }
    }
}

extension CaptureName: CustomDebugStringConvertible {
    public var debugDescription: String { stringValue }
}
