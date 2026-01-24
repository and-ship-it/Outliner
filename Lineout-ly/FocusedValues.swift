//
//  FocusedValues.swift
//  Lineout-ly
//
//  Created by Andriy on 24/01/2026.
//

import SwiftUI

// MARK: - Focused Document

struct FocusedDocumentKey: FocusedValueKey {
    typealias Value = OutlineDocument
}

extension FocusedValues {
    var document: OutlineDocument? {
        get { self[FocusedDocumentKey.self] }
        set { self[FocusedDocumentKey.self] = newValue }
    }
}
