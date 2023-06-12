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
public let Identifier           = ExpressionType(precedence: 20,                        characteristic: .pure)
public let Literal              = ExpressionType(precedence: 20,                        characteristic: .pure)
public let Keyword              = ExpressionType(precedence: 20,                        characteristic: .pure)
// RegExp are objects, and so for example for the FuzzIL program
//     v1 <- CreateRegExp
//     Compare v1, v1
// there is a difference between
//    let a = /a/;
//    a === a;  // (true)
// and
//     /a/ === /a/;  // (false)
// the former being the correct JavaScript equivalent.
public let RegExpLiteral        = ExpressionType(precedence: 20,                        characteristic: .effectful)
public let CallExpression       = ExpressionType(precedence: 19, associativity: .left,  characteristic: .effectful)
public let MemberExpression     = ExpressionType(precedence: 19, associativity: .left,  characteristic: .effectful)
public let NewExpression        = ExpressionType(precedence: 19,                        characteristic: .effectful)
// Artificial, need brackets around some literals for syntactic reasons
public let NumberLiteral        = ExpressionType(precedence: 17,                        characteristic: .pure)
// A helper expression type since negative numbers are technically unary expressions, but then they wouldn't
// be inlined since unary expressions aren't generally pure.
public let NegativeNumberLiteral = ExpressionType(precedence: 17,                        characteristic: .pure)
public let StringLiteral         = ExpressionType(precedence: 17,                        characteristic: .pure)
public let TemplateLiteral       = ExpressionType(precedence: 17,                        characteristic: .effectful)
public let ObjectLiteral         = ExpressionType(precedence: 17,                        characteristic: .effectful)
public let ArrayLiteral          = ExpressionType(precedence: 17,                        characteristic: .effectful)
public let PostfixExpression     = ExpressionType(precedence: 16,                        characteristic: .effectful)
public let UnaryExpression       = ExpressionType(precedence: 15, associativity: .right, characteristic: .effectful)
public let BinaryExpression      = ExpressionType(precedence: 14, associativity: .none,  characteristic: .effectful)
public let TernaryExpression     = ExpressionType(precedence: 4,  associativity: .none,  characteristic: .effectful)
public let AssignmentExpression  = ExpressionType(precedence: 3,                         characteristic: .effectful)
public let YieldExpression       = ExpressionType(precedence: 2,  associativity: .right, characteristic: .effectful)
public let SpreadExpression      = ExpressionType(precedence: 2,                         characteristic: .effectful)
public let CommaExpression       = ExpressionType(precedence: 1,  associativity: .left,  characteristic: .effectful)
