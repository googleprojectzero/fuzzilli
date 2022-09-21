// Copyright 2019 Google LLC
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
// https://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

precedencegroup ExpressionBuilderPrecedence {
    associativity: left
    lowerThan: AdditionPrecedence
    higherThan: AssignmentPrecedence
}

// We use the custom operator <> to build up expressions.
infix operator <> : ExpressionBuilderPrecedence

public enum Associativity: UInt8 {
    case none
    case left
    case right
}

public enum Inlineability: UInt8 {
    case never
    case onlyFollowing
    case singleUseOnly
    case always
}

/// The type of an expression. Also serves as a constructor.
public struct ExpressionType: Equatable {
    static private var nextId: UInt32 = 0

    let id: UInt32
    let precedence: UInt8
    let associativity: Associativity
    let inlineability: Inlineability

    init(precedence: UInt8, associativity: Associativity = .none, inline inlineability: Inlineability = .never) {
        self.id = ExpressionType.nextId
        ExpressionType.nextId += 1
        self.precedence = precedence
        self.associativity = associativity
        self.inlineability = inlineability
    }

    func new(_ initialText: String = "", inline inlineability: Inlineability) -> Expression {
        return Expression(type: self, text: initialText, inlineability: inlineability, numSubexpressions: 0)
    }

    func new(_ initialText: String = "") -> Expression {
        return Expression(type: self, text: initialText, inlineability: inlineability, numSubexpressions: 0)
    }

    public static func ==(lhs: ExpressionType, rhs: ExpressionType) -> Bool {
        return lhs.id == rhs.id
    }
}

/// An expression in the target language.
public struct Expression: CustomStringConvertible {
    public let type: ExpressionType
    public let text: String
    public let inlineability: Inlineability

    let numSubexpressions: UInt8

    public var description: String {
        return text
    }

    func canInline(_ instr: Instruction, _ uses: [Int]) -> Bool {
        switch inlineability {
        case .never:
            return false
        case .onlyFollowing:
            return uses.count == 1 && uses[0] == instr.index + 1
        case .singleUseOnly:
            return uses.count == 1
        case .always:
            // Inlining should not cause instructions to not being emitted at all
            return uses.count > 0
        }
    }

    func needsBrackets(in other: Expression, isLhs: Bool = true) -> Bool {
        if type.precedence == other.type.precedence {
            if type.associativity != other.type.associativity {
                return true
            }
            switch type.associativity {
            case .none:
                return true
            case .left:
                return !isLhs
            case .right:
                return isLhs
            }
        }
        return type.precedence < other.type.precedence
    }

    func extended(by part: String) -> Expression {
        return Expression(type: type,
                          text: text + part,
                          inlineability: inlineability,
                          numSubexpressions: numSubexpressions)
    }

    func extended(by part: Expression) -> Expression {
        let newText: String
        if part.needsBrackets(in: self, isLhs: numSubexpressions == 0) {
            newText = text + "(" + part + ")"
        } else {
            newText = text + part
        }
        return Expression(type: type,
                          text: newText,
                          inlineability: Inlineability(rawValue: min(inlineability.rawValue, part.inlineability.rawValue))!,
                          numSubexpressions: numSubexpressions + 1)
    }

    static func <>(lhs: Expression, rhs: Expression) -> Expression {
        return lhs.extended(by: rhs)
    }

    static func <>(lhs: Expression, rhs: String) -> Expression {
        return lhs.extended(by: rhs)
    }

    static func <>(lhs: Expression, rhs: Int64) -> Expression {
        return lhs.extended(by: String(rhs))
    }

    static func +(lhs: String, rhs: Expression) -> String {
        return lhs + rhs.text
    }
}
