// PathUtils.swift - Utilities for parsing paths and navigating element hierarchies.

import ApplicationServices // For Element, AXUIElement and kAX...Attribute constants
import Foundation

// Assumes Element is defined (likely via AXSwift an extension or typealias)
// debug() is assumed to be globally available from Logging.swift
// axValue<T>() is assumed to be globally available from ValueHelpers.swift
// kAXWindowRole, kAXWindowsAttribute, kAXChildrenAttribute, kAXRoleAttribute from AccessibilityConstants.swift
