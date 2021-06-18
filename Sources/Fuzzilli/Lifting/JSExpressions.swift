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

// JavaScript expressions. See https://developer.mozilla.org/en-US/docs/Web/JavaScript/Reference/Operators/Operator_Precedence
public let Identifier           = ExpressionType(precedence: 20,                        inline: .always)
public let Literal              = ExpressionType(precedence: 20,                        inline: .always)
public let CallExpression       = ExpressionType(precedence: 19, associativity: .left,  inline: .onlyFollowing)
public let MemberExpression     = ExpressionType(precedence: 19, associativity: .left,  inline: .onlyFollowing)
public let NewExpression        = ExpressionType(precedence: 19,                        inline: .never)
// Artificial, need brackets around some literals for syntactic reasons
public let NumberLiteral        = ExpressionType(precedence: 17,                        inline: .always)
public let ObjectLiteral        = ExpressionType(precedence: 17,                        inline: .singleUseOnly)
public let ArrayLiteral         = ExpressionType(precedence: 17,                        inline: .singleUseOnly)
public let PostfixExpression    = ExpressionType(precedence: 16,                        inline: .singleUseOnly)
public let UnaryExpression      = ExpressionType(precedence: 15, associativity: .right, inline: .singleUseOnly)
public let BinaryExpression     = ExpressionType(precedence: 14, associativity: .none,  inline: .singleUseOnly)
public let TernaryExpression    = ExpressionType(precedence: 4,  associativity: .none,  inline: .singleUseOnly)
public let AssignmentExpression = ExpressionType(precedence: 3,                         inline: .never)
public let ListExpression       = ExpressionType(precedence: 1,  associativity: .left,  inline: .never)

public struct InlineOnlyLiterals: InliningPolicy {
    public init() {}
    
    public func shouldInline(_ expr: Expression) -> Bool {
        return expr.type == Literal || expr.type == NumberLiteral || expr.type == Identifier
    }
}
