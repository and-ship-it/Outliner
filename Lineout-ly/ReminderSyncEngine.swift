//
//  ReminderSyncEngine.swift
//  Lineout-ly
//
//  Created by Andriy on 27/01/2026.
//

import EventKit
import Foundation
#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// Bidirectional sync engine between Lineout-ly outline nodes and Apple Reminders.
/// Outbound: task toggle/completion/title changes push to Reminders.
/// Inbound: EKEventStoreChanged pulls external changes into the document.
@Observable
@MainActor
final class ReminderSyncEngine {
    static let shared = ReminderSyncEngine()

    private let eventStore = EKEventStore()

    /// Whether the user has granted Reminders access
    var isAuthorized = false

    /// Flag to prevent sync loops during inbound sync.
    /// Checked by outbound hooks to avoid re-syncing changes we just applied.
    var isApplyingReminderChanges = false

    /// Debounce timer for EKEventStoreChanged notifications
    private var debounceTask: Task<Void, Never>?

    /// Per-node debounce timers for title sync (avoids syncing on every keystroke)
    private var titleSyncTasks: [UUID: Task<Void, Never>] = [:]

    private init() {}

    // MARK: - Authorization

    /// Request access to Apple Reminders. Returns true if granted.
    func requestAccess() async -> Bool {
        if #available(macOS 14.0, iOS 17.0, *) {
            do {
                let granted = try await eventStore.requestFullAccessToReminders()
                isAuthorized = granted
                print("[Reminders] Full access \(granted ? "granted" : "denied")")
                return granted
            } catch {
                print("[Reminders] Authorization error: \(error)")
                isAuthorized = false
                return false
            }
        } else {
            do {
                let granted = try await eventStore.requestAccess(to: .reminder)
                isAuthorized = granted
                print("[Reminders] Access \(granted ? "granted" : "denied")")
                return granted
            } catch {
                print("[Reminders] Authorization error: \(error)")
                isAuthorized = false
                return false
            }
        }
    }

    // MARK: - Observation

    /// Start observing changes from Apple Reminders (EKEventStoreChanged notification).
    /// Debounces by 500ms to avoid rapid-fire updates.
    func startObserving() {
        NotificationCenter.default.addObserver(
            forName: .EKEventStoreChanged,
            object: eventStore,
            queue: nil
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.handleStoreChanged()
            }
        }
        print("[Reminders] Started observing EKEventStoreChanged")
    }

    /// Debounced handler for store changes
    private func handleStoreChanged() {
        debounceTask?.cancel()
        debounceTask = Task {
            try? await Task.sleep(nanoseconds: 500_000_000) // 500ms debounce
            guard !Task.isCancelled else { return }
            await syncExternalChanges()
        }
    }

    // MARK: - Outbound Sync (Lineout → Reminders)

    /// Create or update a reminder for the given node.
    /// Called when a task is toggled/completed under a date node.
    func syncNodeToReminder(_ node: OutlineNode, dueDate: Date?) {
        guard isAuthorized else { return }

        do {
            if let existingId = node.reminderIdentifier,
               let existing = eventStore.calendarItem(withIdentifier: existingId) as? EKReminder {
                // Update existing reminder
                existing.title = node.title
                existing.isCompleted = node.isTask && node.isTaskCompleted
                if let date = dueDate {
                    var comps = Calendar.current.dateComponents([.year, .month, .day], from: date)
                    // Include time if node has it
                    if let hour = node.reminderTimeHour, let minute = node.reminderTimeMinute {
                        comps.hour = hour
                        comps.minute = minute
                    }
                    existing.dueDateComponents = comps
                }
                // Sync metadata children (notes + link) to reminder
                syncMetadataChildrenOutbound(from: node, to: existing)
                try eventStore.save(existing, commit: true)
                // Update list name in case calendar changed
                node.reminderListName = existing.calendar?.title
                print("[Reminders] Updated reminder: \(node.title)")
            } else {
                // Create new reminder
                let reminder = EKReminder(eventStore: eventStore)
                reminder.title = node.title
                reminder.isCompleted = node.isTask && node.isTaskCompleted

                if let date = dueDate {
                    var comps = Calendar.current.dateComponents([.year, .month, .day], from: date)
                    if let hour = node.reminderTimeHour, let minute = node.reminderTimeMinute {
                        comps.hour = hour
                        comps.minute = minute
                    }
                    reminder.dueDateComponents = comps
                }

                // Sync metadata children (notes + link) to reminder
                syncMetadataChildrenOutbound(from: node, to: reminder)

                // Use default reminders calendar
                reminder.calendar = eventStore.defaultCalendarForNewReminders()

                try eventStore.save(reminder, commit: true)

                // Store the identifier for future sync
                node.reminderIdentifier = reminder.calendarItemIdentifier
                node.reminderListName = reminder.calendar?.title
                print("[Reminders] Created reminder: \(node.title) (id: \(reminder.calendarItemIdentifier))")
            }
        } catch {
            print("[Reminders] Error syncing node to reminder: \(error)")
        }
    }

    /// Remove the reminder linked to a node (e.g., when un-toggling task under date node).
    func removeReminder(for node: OutlineNode) {
        guard isAuthorized,
              let reminderId = node.reminderIdentifier,
              let reminder = eventStore.calendarItem(withIdentifier: reminderId) as? EKReminder else {
            // Clear link even if reminder not found
            node.reminderIdentifier = nil
            node.reminderListName = nil
            node.reminderTimeHour = nil
            node.reminderTimeMinute = nil
            removeMetadataChildren(from: node)
            return
        }

        do {
            try eventStore.remove(reminder, commit: true)
            node.reminderIdentifier = nil
            node.reminderListName = nil
            node.reminderTimeHour = nil
            node.reminderTimeMinute = nil
            removeMetadataChildren(from: node)
            print("[Reminders] Removed reminder for: \(node.title)")
        } catch {
            print("[Reminders] Error removing reminder: \(error)")
        }
    }

    /// Update the due date for a synced reminder (e.g., when dragging between date nodes).
    func updateDueDate(for node: OutlineNode, newDate: Date?) {
        guard isAuthorized,
              let reminderId = node.reminderIdentifier,
              let reminder = eventStore.calendarItem(withIdentifier: reminderId) as? EKReminder else {
            return
        }

        do {
            if let date = newDate {
                var comps = Calendar.current.dateComponents([.year, .month, .day], from: date)
                // Preserve existing time component
                if let hour = node.reminderTimeHour, let minute = node.reminderTimeMinute {
                    comps.hour = hour
                    comps.minute = minute
                }
                reminder.dueDateComponents = comps
            } else {
                reminder.dueDateComponents = nil
            }
            try eventStore.save(reminder, commit: true)
            print("[Reminders] Updated due date for: \(node.title)")
        } catch {
            print("[Reminders] Error updating due date: \(error)")
        }
    }

    /// Debounced title sync — avoids updating reminders on every keystroke.
    /// Waits 1 second after last change before syncing.
    /// Also handles metadata children: if the edited node is a note/link child,
    /// syncs the metadata to the parent reminder instead.
    func scheduleTitleSync(for node: OutlineNode) {
        // If this is a metadata child, sync its parent reminder instead
        if let childType = node.reminderChildType,
           let parent = node.parent,
           parent.reminderIdentifier != nil {
            titleSyncTasks[node.id]?.cancel()
            titleSyncTasks[node.id] = Task {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                guard !Task.isCancelled else { return }
                titleSyncTasks.removeValue(forKey: node.id)
                self.syncMetadataChildToReminder(node, childType: childType, parent: parent)
            }
            return
        }

        guard node.reminderIdentifier != nil else { return }
        titleSyncTasks[node.id]?.cancel()
        titleSyncTasks[node.id] = Task {
            try? await Task.sleep(nanoseconds: 1_000_000_000) // 1 second debounce
            guard !Task.isCancelled else { return }
            titleSyncTasks.removeValue(forKey: node.id)
            let dueDate = DateStructureManager.shared.inferredDueDate(for: node)
            syncNodeToReminder(node, dueDate: dueDate)
        }
    }

    // MARK: - Inbound Sync (Reminders → Lineout)

    /// Fetch external changes from Apple Reminders and sync them into the document.
    /// Step 1: Update existing synced nodes from their reminders.
    /// Step 2: Import new external reminders due this week.
    func syncExternalChanges() async {
        guard isAuthorized else { return }
        guard let document = WindowManager.shared.document else { return }
        guard !isApplyingReminderChanges else { return }
        guard !document.isApplyingRemoteChanges else { return }

        isApplyingReminderChanges = true
        defer { isApplyingReminderChanges = false }

        var didChange = false

        // Step 1: Update existing synced nodes from their linked reminders
        let syncedNodes = document.root.flattened().filter { $0.reminderIdentifier != nil && $0.reminderChildType == nil }
        for node in syncedNodes {
            guard let remId = node.reminderIdentifier else { continue }

            if let reminder = eventStore.calendarItem(withIdentifier: remId) as? EKReminder {
                var nodeChanged = false

                // Sync title
                let remTitle = reminder.title ?? ""
                if node.title != remTitle {
                    node.title = remTitle
                    nodeChanged = true
                }

                // Sync completion
                if node.isTask && node.isTaskCompleted != reminder.isCompleted {
                    node.isTaskCompleted = reminder.isCompleted
                    nodeChanged = true
                }

                // Sync list name
                let listName = reminder.calendar?.title
                if node.reminderListName != listName {
                    node.reminderListName = listName
                    nodeChanged = true
                }

                // Sync time
                let remHour = reminder.dueDateComponents?.hour
                let remMinute = reminder.dueDateComponents?.minute
                if node.reminderTimeHour != remHour || node.reminderTimeMinute != remMinute {
                    // Only update if reminder actually has a time (hour != nil and is valid)
                    if let h = remHour, h != Int(NSNotFound), let m = remMinute, m != Int(NSNotFound) {
                        node.reminderTimeHour = h
                        node.reminderTimeMinute = m
                    } else if node.reminderTimeHour != nil {
                        // Time was removed
                        node.reminderTimeHour = nil
                        node.reminderTimeMinute = nil
                    }
                    nodeChanged = true
                }

                // Sync due date — detect date changes and move node accordingly
                if let remDueDate = reminder.dueDateComponents.flatMap({ Calendar.current.date(from: $0) }) {
                    let currentDate = DateStructureManager.shared.inferredDueDate(for: node)
                    let cal = Calendar.current
                    let remDay = cal.startOfDay(for: remDueDate)
                    let curDay = currentDate.map { cal.startOfDay(for: $0) }

                    if remDay != curDay {
                        // Due date changed — determine if within or beyond current week
                        let weekDatesForMove = DateStructureManager.shared.currentWeekDates()
                        let weekStartDays = Set(weekDatesForMove.map { cal.startOfDay(for: $0) })

                        if weekStartDays.contains(remDay),
                           let newDateNode = DateStructureManager.shared.dateNode(for: remDueDate, in: document) {
                            // Within current week — move node to new date
                            node.removeFromParent()
                            insertNodeSortedByTime(node, under: newDateNode)
                            didChange = true
                            print("[Reminders] Moved reminder to new date: \(node.title) → \(newDateNode.title)")
                        } else {
                            // Beyond current week — handle detachment
                            handleReminderMovedBeyondWeek(node: node, reminderTitle: reminder.title ?? "")
                            didChange = true
                            print("[Reminders] Reminder moved beyond week: \(node.title)")
                            continue // Node was detached, skip further updates
                        }
                    }
                }

                // Sync notes → metadata child
                if syncNotesInbound(from: reminder, to: node) { nodeChanged = true }

                // Sync URL → metadata child
                if syncLinkInbound(from: reminder, to: node) { nodeChanged = true }

                if nodeChanged {
                    document.contentDidChange(nodeId: node.id)
                    didChange = true
                }
            } else {
                // Reminder was deleted externally — remove sync link, keep node as plain bullet
                node.reminderIdentifier = nil
                node.reminderListName = nil
                node.reminderTimeHour = nil
                node.reminderTimeMinute = nil
                // Remove metadata children
                removeMetadataChildren(from: node)
                didChange = true
                print("[Reminders] Removed sync link for deleted reminder: \(node.title)")
            }
        }

        // Step 2: Fetch new external reminders due this week
        let weekDates = DateStructureManager.shared.currentWeekDates()
        guard let weekStart = weekDates.first,
              let weekEndPlusOne = Calendar.current.date(byAdding: .day, value: 1, to: weekDates.last ?? Date()) else {
            if didChange {
                document.structureVersion += 1
                iCloudManager.shared.scheduleAutoSave(for: document)
            }
            return
        }

        let predicate = eventStore.predicateForIncompleteReminders(
            withDueDateStarting: weekStart,
            ending: weekEndPlusOne,
            calendars: nil
        )

        let reminders = await fetchReminders(matching: predicate)

        // Build set of already-tracked reminder IDs
        let trackedIds = Set(syncedNodes.compactMap { $0.reminderIdentifier })

        for reminder in reminders {
            let remId = reminder.calendarItemIdentifier
            guard !trackedIds.contains(remId) else { continue }

            // New external reminder — create node under the appropriate date
            guard let dueDateComponents = reminder.dueDateComponents,
                  let dueDate = Calendar.current.date(from: dueDateComponents),
                  let dateNode = DateStructureManager.shared.dateNode(for: dueDate, in: document) else {
                continue
            }

            let newNode = OutlineNode(title: reminder.title ?? "")
            newNode.isTask = true
            newNode.isTaskCompleted = reminder.isCompleted
            newNode.reminderIdentifier = remId
            newNode.reminderListName = reminder.calendar?.title

            // Sync time
            if let h = reminder.dueDateComponents?.hour, h != Int(NSNotFound),
               let m = reminder.dueDateComponents?.minute, m != Int(NSNotFound) {
                newNode.reminderTimeHour = h
                newNode.reminderTimeMinute = m
            }

            // Insert sorted by time (new imports only)
            insertNodeSortedByTime(newNode, under: dateNode)

            // Sync notes → metadata child
            _ = syncNotesInbound(from: reminder, to: newNode)

            // Sync URL → metadata child
            _ = syncLinkInbound(from: reminder, to: newNode)

            didChange = true
            print("[Reminders] Created node from external reminder: \(reminder.title ?? "")")
        }

        if didChange {
            document.structureVersion += 1
            iCloudManager.shared.scheduleAutoSave(for: document)
        }
    }

    // MARK: - Helpers

    /// Async wrapper around EventKit's completion-handler-based fetchReminders
    private func fetchReminders(matching predicate: NSPredicate) async -> [EKReminder] {
        await withCheckedContinuation { continuation in
            eventStore.fetchReminders(matching: predicate) { reminders in
                continuation.resume(returning: reminders ?? [])
            }
        }
    }

    /// Check if a node is under a date node (has an inferred due date)
    func isUnderDateNode(_ node: OutlineNode) -> Bool {
        DateStructureManager.shared.inferredDueDate(for: node) != nil
    }

    // MARK: - Open in Reminders

    /// Open the linked reminder in the Apple Reminders app.
    func openInReminders(_ node: OutlineNode) {
        guard let remId = node.reminderIdentifier else { return }

        // Try x-apple-reminderkit deep link first, fallback to Reminders app
        let deepLink = URL(string: "x-apple-reminderkit://REMCDReminder/\(remId)")
        let fallback = URL(string: "x-apple-reminders://")

        let urlToOpen = deepLink ?? fallback
        guard let url = urlToOpen else { return }

        #if os(macOS)
        NSWorkspace.shared.open(url)
        #else
        UIApplication.shared.open(url)
        #endif
    }

    // MARK: - Sorted Insertion

    /// Insert a new node under a date node, sorted by time.
    /// Nodes without time go to the end. Only used for new imports — existing nodes are not re-sorted.
    private func insertNodeSortedByTime(_ node: OutlineNode, under dateNode: OutlineNode) {
        guard let hour = node.reminderTimeHour, let minute = node.reminderTimeMinute else {
            // No time — append at end
            dateNode.addChild(node)
            return
        }

        let nodeMinutes = hour * 60 + minute

        // Find first child with a later time (or no time) to insert before
        for (index, child) in dateNode.children.enumerated() {
            if let childHour = child.reminderTimeHour, let childMin = child.reminderTimeMinute {
                if childHour * 60 + childMin > nodeMinutes {
                    dateNode.addChild(node, at: index)
                    return
                }
            } else {
                // Child has no time — insert before it (timed items come first)
                dateNode.addChild(node, at: index)
                return
            }
        }

        // All existing children have earlier times — append at end
        dateNode.addChild(node)
    }

    // MARK: - Metadata Children Sync (Notes + Links)

    /// Sync a single metadata child's content to its parent's reminder.
    /// Called when a metadata child's title is edited.
    private func syncMetadataChildToReminder(_ child: OutlineNode, childType: String, parent: OutlineNode) {
        guard isAuthorized,
              let remId = parent.reminderIdentifier,
              let reminder = eventStore.calendarItem(withIdentifier: remId) as? EKReminder else { return }

        do {
            if childType == "note" {
                reminder.notes = child.title
            } else if childType == "link" {
                // Parse URL from title (might be markdown link or plain URL)
                reminder.url = extractURL(from: child.title)
            }
            try eventStore.save(reminder, commit: true)
            print("[Reminders] Synced metadata child (\(childType)) to reminder: \(parent.title)")
        } catch {
            print("[Reminders] Error syncing metadata child: \(error)")
        }
    }

    /// Sync metadata children from a node outbound to the given EKReminder.
    /// Called during syncNodeToReminder to push notes + link to Reminders.
    private func syncMetadataChildrenOutbound(from node: OutlineNode, to reminder: EKReminder) {
        // Notes
        let noteChild = node.children.first { $0.reminderChildType == "note" }
        reminder.notes = noteChild?.title

        // URL
        let linkChild = node.children.first { $0.reminderChildType == "link" }
        if let linkTitle = linkChild?.title {
            reminder.url = extractURL(from: linkTitle)
        } else {
            reminder.url = nil
        }
    }

    /// Sync notes from a reminder inbound to the node's metadata children.
    /// Returns true if any change was made.
    @discardableResult
    private func syncNotesInbound(from reminder: EKReminder, to node: OutlineNode) -> Bool {
        let existingNoteChild = node.children.first { $0.reminderChildType == "note" }
        let notes = reminder.notes?.trimmingCharacters(in: .whitespacesAndNewlines)
        let hasNotes = notes != nil && !notes!.isEmpty

        if hasNotes {
            if let child = existingNoteChild {
                // Update if different
                if child.title != notes! {
                    child.title = notes!
                    return true
                }
            } else {
                // Create new note child
                let noteNode = OutlineNode(title: notes!)
                noteNode.reminderChildType = "note"
                node.addChild(noteNode, at: 0) // Notes go first among children
                return true
            }
        } else if let child = existingNoteChild {
            // Notes cleared externally — remove child
            child.removeFromParent()
            return true
        }

        return false
    }

    /// Sync URL from a reminder inbound to the node's metadata children.
    /// Returns true if any change was made.
    @discardableResult
    private func syncLinkInbound(from reminder: EKReminder, to node: OutlineNode) -> Bool {
        let existingLinkChild = node.children.first { $0.reminderChildType == "link" }
        let url = reminder.url

        if let url = url {
            let urlString = url.absoluteString
            if let child = existingLinkChild {
                // Update if different (compare raw URLs)
                let existingURL = extractURL(from: child.title)?.absoluteString
                if existingURL != urlString {
                    child.title = urlString
                    return true
                }
            } else {
                // Create new link child
                let linkNode = OutlineNode(title: urlString)
                linkNode.reminderChildType = "link"
                // Insert after note child if it exists, otherwise at position 0
                let insertIndex = node.children.firstIndex(where: { $0.reminderChildType != "note" }) ?? node.children.count
                node.addChild(linkNode, at: insertIndex)
                return true
            }
        } else if let child = existingLinkChild {
            // URL cleared externally — remove child
            child.removeFromParent()
            return true
        }

        return false
    }

    /// Remove all metadata children (note + link) from a node.
    private func removeMetadataChildren(from node: OutlineNode) {
        let metaChildren = node.children.filter { $0.reminderChildType != nil }
        for child in metaChildren {
            child.removeFromParent()
        }
    }

    /// Handle a reminder whose due date moved beyond the current week.
    /// - If the node has user-created children: keep them as a stub with "(moved)" suffix
    /// - If only metadata children (or none): delete the node entirely
    private func handleReminderMovedBeyondWeek(node: OutlineNode, reminderTitle: String) {
        // Identify user-created children (not reminder metadata)
        let userChildren = node.children.filter { $0.reminderChildType == nil }

        if userChildren.isEmpty {
            // No user content — delete the node entirely
            node.removeFromParent()
            print("[Reminders] Deleted node with no user content: \(reminderTitle)")
        } else {
            // User content exists — convert to a plain stub
            // Remove reminder metadata children (note, link)
            removeMetadataChildren(from: node)
            // Append "(moved)" to the title
            let baseName = reminderTitle.isEmpty ? node.title : reminderTitle
            node.title = baseName + " (moved)"
            // Strip all reminder sync data so it becomes a plain bullet
            node.reminderIdentifier = nil
            node.reminderListName = nil
            node.reminderTimeHour = nil
            node.reminderTimeMinute = nil
            // Convert from task to plain bullet
            node.isTask = false
            node.isTaskCompleted = false
            print("[Reminders] Converted to stub with \(userChildren.count) user children: \(node.title)")
        }
    }

    /// Extract a URL from a string (handles both plain URLs and markdown links).
    private func extractURL(from text: String) -> URL? {
        // Check for markdown link format: [title](url)
        if let urlRange = text.range(of: #"\[.*?\]\((.*?)\)"#, options: .regularExpression) {
            let match = text[urlRange]
            if let openParen = match.firstIndex(of: "("),
               let closeParen = match.lastIndex(of: ")") {
                let urlString = String(match[match.index(after: openParen)..<closeParen])
                return URL(string: urlString)
            }
        }
        // Try plain URL
        return URL(string: text.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    /// Sync metadata children from a parent node outbound to Reminders.
    /// Public version called from NodeRow when metadata child content changes.
    func syncMetadataChildrenToReminder(_ parentNode: OutlineNode) {
        guard isAuthorized, !isApplyingReminderChanges,
              let remId = parentNode.reminderIdentifier,
              let reminder = eventStore.calendarItem(withIdentifier: remId) as? EKReminder else { return }

        do {
            syncMetadataChildrenOutbound(from: parentNode, to: reminder)
            try eventStore.save(reminder, commit: true)
            print("[Reminders] Synced metadata children for: \(parentNode.title)")
        } catch {
            print("[Reminders] Error syncing metadata children: \(error)")
        }
    }
}
