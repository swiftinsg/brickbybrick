//
//  NewTaskView.swift
//  focushouse
//
//  Created by T Krobot on 11/11/26.
//

import Foundation
import SwiftUI
import SwiftData

struct NewTaskView: View {
    @Environment(\.modelContext) var modelContext
    @Environment(\.dismiss) var dismiss

    @State private var name = ""
    @State private var selectedTag = "Work"
    let tags = ["Work", "Hobbies"]
    @State private var dueDate = Date.now
    @State private var priority: Priority = .medium

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        NavigationStack {
            Form {
                TextField("Name", text: $name)
            
                Picker("Tag", selection: $selectedTag) {
                    ForEach(tags, id: \.self) { tag in
                        Text(tag)
                    }
                }

                DatePicker("Due date", selection: $dueDate, displayedComponents: .date)

                Picker("Priority", selection: $priority) {
                    ForEach(Priority.allCases, id: \.self) { priority in
                        Text(priority.rawValue)
                            .tag(priority)
                    }
                }
            }
            .pixelTitle("New Task")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                        .disabled(trimmedName.isEmpty)
                }
            }
        }
    }

    func save() {
        let task = TodoItem(
            name: trimmedName,
            selectedTag: selectedTag,
            dueDate: dueDate,
            priority: priority
        )

        modelContext.insert(task)
        dismiss()
    }
}

#Preview {
    NewTaskView()
        .modelContainer(for: TodoItem.self, inMemory: true)
}
