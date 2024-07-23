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

/// The type of an expression. Also serves as a constructor.
public class ExpressionType {
    let precedence: UInt8
    let associativity: Associativity
    let characteristic: Characteristic

    init(precedence: UInt8, associativity: Associativity = .none, characteristic: Characteristic) {
        self.precedence = precedence
        self.associativity = associativity
        self.characteristic = characteristic
    }

    func new(_ initialText: String = "") -> Expression {
        return Expression(type: self, text: initialText, numSubexpressions: 0)
    }

    public enum Associativity: UInt8 {
        case none
        case left
        case right
    }

    // Whether an expression can have side effects or not. An effectful expression can only be inlined
    // as long as it still executes before any other effectful operation that comes after it.
    public enum Characteristic: UInt8 {
        // The expression is pure and so can be inlined multiple times, across different blocks in the CFG
        case pure
        // The expression may have side effects so can only be inlined if:
        // - There is a single use of the value
        // - The use happens inside the same block in the CFG
        // - No other effectful expressions happens between this expression and its use
        case effectful
    }
}

/// An expression in the target language.
public struct Expression: CustomStringConvertible {
    public let type: ExpressionType
    public let text: String

    let numSubexpressions: UInt

    public var characteristic: ExpressionType.Characteristic {
        return type.characteristic
    }

    public var isEffectful: Bool {
        return characteristic == .effectful
    }

    public var description: String {
        return text
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
                          numSubexpressions: numSubexpressions)
    }

    func extended(by part: Expression) -> Expression {
        let newText: String
        if part.needsBrackets(in: self, isLhs: numSubexpressions == 0) {
            newText = text + "(" + part.text + ")"
        } else {
            newText = text + part.text
        }
        return Expression(type: type,
                          text: newText,
                          numSubexpressions: numSubexpressions + 1)
    }

    static func +(lhs: Expression, rhs: Expression) -> Expression {
        return lhs.extended(by: rhs)
    }

    static func +(lhs: Expression, rhs: String) -> Expression {
        return lhs.extended(by: rhs)
    }

    static func +(lhs: Expression, rhs: Int64) -> Expression {
        return lhs.extended(by: String(rhs))
    }
}
