//
//  AXValue+Extensions.swift
//  AXorcist
//
//  Extensions for AXValue to simplify value extraction and creation
//

import ApplicationServices
import CoreGraphics
import Foundation

extension AXValue {
    // MARK: - Value Extraction

    /// Extract CGSize from AXValue
    public func cgSize() -> CGSize? {
        guard AXValueGetType(self) == .cgSize else { return nil }
        var size = CGSize.zero
        let success = AXValueGetValue(self, .cgSize, &size)
        return success ? size : nil
    }

    /// Extract CGPoint from AXValue
    public func cgPoint() -> CGPoint? {
        guard AXValueGetType(self) == .cgPoint else { return nil }
        var point = CGPoint.zero
        let success = AXValueGetValue(self, .cgPoint, &point)
        return success ? point : nil
    }

    /// Extract CGRect from AXValue
    public func cgRect() -> CGRect? {
        guard AXValueGetType(self) == .cgRect else { return nil }
        var rect = CGRect.zero
        let success = AXValueGetValue(self, .cgRect, &rect)
        return success ? rect : nil
    }

    /// Extract CFRange from AXValue
    public func cfRange() -> CFRange? {
        guard AXValueGetType(self) == .cfRange else { return nil }
        var range = CFRange()
        let success = AXValueGetValue(self, .cfRange, &range)
        return success ? range : nil
    }

    /// Extract AXError from AXValue
    public func axError() -> AXError? {
        guard AXValueGetType(self) == .axError else { return nil }
        var error: AXError = .failure
        let success = AXValueGetValue(self, .axError, &error)
        return success ? error : nil
    }

    /// Get the type of this AXValue
    public var valueType: AXValueType {
        return AXValueGetType(self)
    }

    /// Extract value as Any?, automatically determining the type
    public func value() -> Any? {
        let type = self.valueType

        switch type {
        case .axError:
            return axError()
        case .cgSize:
            return cgSize()
        case .cgPoint:
            return cgPoint()
        case .cgRect:
            return cgRect()
        case .cfRange:
            return cfRange()
        case .illegal:
            return nil
        @unknown default:
            return nil
        }
    }

    // MARK: - Static Factory Methods

    /// Create AXValue from CGPoint
    public static func create(point: CGPoint) -> AXValue? {
        var point = point
        return AXValueCreate(.cgPoint, &point)
    }

    /// Create AXValue from CGSize
    public static func create(size: CGSize) -> AXValue? {
        var size = size
        return AXValueCreate(.cgSize, &size)
    }

    /// Create AXValue from CGRect
    public static func create(rect: CGRect) -> AXValue? {
        var rect = rect
        return AXValueCreate(.cgRect, &rect)
    }

    /// Create AXValue from CFRange
    public static func create(range: CFRange) -> AXValue? {
        var range = range
        return AXValueCreate(.cfRange, &range)
    }

    /// Create AXValue from AXError
    public static func create(error: AXError) -> AXValue? {
        var error = error
        return AXValueCreate(.axError, &error)
    }
}
