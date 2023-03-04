//
//  PropertyBuilder.swift
//
//  MIT License
//
//  Copyright (c) 2022 RequestDL
//
//  Permission is hereby granted, free of charge, to any person obtaining a copy
//  of this software and associated documentation files (the "Software"), to deal
//  in the Software without restriction, including without limitation the rights
//  to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
//  copies of the Software, and to permit persons to whom the Software is
//  furnished to do so, subject to the following conditions:
//
//  The above copyright notice and this permission notice shall be included in all
//  copies or substantial portions of the Software.
//
//  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
//  IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
//  FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
//  AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
//  LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
//  OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
//  SOFTWARE.
//

import Foundation

@resultBuilder
public struct PropertyBuilder {

    public static func buildBlock() -> EmptyProperty {
        EmptyProperty()
    }

    public static func buildBlock<Content: Property>(_ component: Content) -> Content {
        component
    }

    public static func buildIf<Content: Property>(_ content: Content?) -> _OptionalContent<Content> {
        _OptionalContent(content)
    }

    public static func buildEither<
        TrueProperty: Property,
        FalseProperty: Property
    >(first: TrueProperty) -> _ConditionalContent<TrueProperty, FalseProperty> {
        _ConditionalContent(first: first)
    }

    public static func buildEither<
        TrueProperty: Property,
        FalseProperty: Property
    >(second: FalseProperty) -> _ConditionalContent<TrueProperty, FalseProperty> {
        _ConditionalContent(second: second)
    }

    public static func buildLimitedAvailability<Content: Property>(_ component: Content) -> Content {
        component
    }
}

// swiftlint:disable function_parameter_count identifier_name large_tuple
extension PropertyBuilder {

    public static func buildBlock<
        C0: Property,
        C1: Property
    >(
        _ c0: C0,
        _ c1: C1
    ) -> _TupleContent<(C0, C1)> {
        _TupleContent {
            await C0.makeProperty(c0, $0)
            await C1.makeProperty(c1, $0)
        }
    }

    public static func buildBlock<
        C0: Property,
        C1: Property,
        C2: Property
    >(
        _ c0: C0,
        _ c1: C1,
        _ c2: C2
    ) -> _TupleContent<(C0, C1, C2)> {
        _TupleContent {
            await C0.makeProperty(c0, $0)
            await C1.makeProperty(c1, $0)
            await C2.makeProperty(c2, $0)
        }
    }

    public static func buildBlock<
        C0: Property,
        C1: Property,
        C2: Property,
        C3: Property
    >(
        _ c0: C0,
        _ c1: C1,
        _ c2: C2,
        _ c3: C3
    ) -> _TupleContent<(C0, C1, C2, C3)> {
        _TupleContent {
            await C0.makeProperty(c0, $0)
            await C1.makeProperty(c1, $0)
            await C2.makeProperty(c2, $0)
            await C3.makeProperty(c3, $0)
        }
    }

    public static func buildBlock<
        C0: Property,
        C1: Property,
        C2: Property,
        C3: Property,
        C4: Property
    >(
        _ c0: C0,
        _ c1: C1,
        _ c2: C2,
        _ c3: C3,
        _ c4: C4
    ) -> _TupleContent<(C0, C1, C2, C3, C4)> {
        _TupleContent {
            await C0.makeProperty(c0, $0)
            await C1.makeProperty(c1, $0)
            await C2.makeProperty(c2, $0)
            await C3.makeProperty(c3, $0)
            await C4.makeProperty(c4, $0)
        }
    }

    public static func buildBlock<
        C0: Property,
        C1: Property,
        C2: Property,
        C3: Property,
        C4: Property,
        C5: Property
    >(
        _ c0: C0,
        _ c1: C1,
        _ c2: C2,
        _ c3: C3,
        _ c4: C4,
        _ c5: C5
    ) -> _TupleContent<(C0, C1, C2, C3, C4, C5)> {
        _TupleContent {
            await C0.makeProperty(c0, $0)
            await C1.makeProperty(c1, $0)
            await C2.makeProperty(c2, $0)
            await C3.makeProperty(c3, $0)
            await C4.makeProperty(c4, $0)
            await C5.makeProperty(c5, $0)
        }
    }

    public static func buildBlock<
        C0: Property,
        C1: Property,
        C2: Property,
        C3: Property,
        C4: Property,
        C5: Property,
        C6: Property
    >(
        _ c0: C0,
        _ c1: C1,
        _ c2: C2,
        _ c3: C3,
        _ c4: C4,
        _ c5: C5,
        _ c6: C6
    ) -> _TupleContent<(C0, C1, C2, C3, C4, C5, C6)> {
        _TupleContent {
            await C0.makeProperty(c0, $0)
            await C1.makeProperty(c1, $0)
            await C2.makeProperty(c2, $0)
            await C3.makeProperty(c3, $0)
            await C4.makeProperty(c4, $0)
            await C5.makeProperty(c5, $0)
            await C6.makeProperty(c6, $0)
        }
    }

    public static func buildBlock<
        C0: Property,
        C1: Property,
        C2: Property,
        C3: Property,
        C4: Property,
        C5: Property,
        C6: Property,
        C7: Property
    >(
        _ c0: C0,
        _ c1: C1,
        _ c2: C2,
        _ c3: C3,
        _ c4: C4,
        _ c5: C5,
        _ c6: C6,
        _ c7: C7
    ) -> _TupleContent<(C0, C1, C2, C3, C4, C5, C6, C7)> {
        _TupleContent {
            await C0.makeProperty(c0, $0)
            await C1.makeProperty(c1, $0)
            await C2.makeProperty(c2, $0)
            await C3.makeProperty(c3, $0)
            await C4.makeProperty(c4, $0)
            await C5.makeProperty(c5, $0)
            await C6.makeProperty(c6, $0)
            await C7.makeProperty(c7, $0)
        }
    }
}
