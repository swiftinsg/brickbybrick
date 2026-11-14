//
//  TodoItem.swift
//  focushouse
//
//  Created by T Krobot on 11/11/26.
//

import Foundation
import SwiftData

enum Priority: String, Codable, CaseIterable, Identifiable {
    case low = "Low"
    case medium = "Medium"
    case high = "High"

    var id: String { rawValue }

    var exclamationCount: Int {
        switch self {
        case .low: return 1
        case .medium: return 2
        case .high: return 3
        }
    }
}

@Model
class TodoItem {
    var name: String = "New Task"
    var selectedTag: String = "Tag"
    var isDone: Bool = false
    var priority: Priority = Priority.medium
    var dueDate: Date = Date.now


    init(name: String, selectedTag: String, dueDate: Date, priority: Priority = .medium) {
        self.name = name
        self.selectedTag = selectedTag
        self.dueDate = dueDate
        self.priority = priority
    }
}
