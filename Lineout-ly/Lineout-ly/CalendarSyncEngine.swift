//
//  CalendarSyncEngine.swift
//  Lineout-ly
//
//  Created by Andriy on 28/01/2026.
//

import EventKit
import Foundation

/// One-way sync engine: Apple Calendar → Lineout-ly outline nodes.
/// Calendar events appear as read-only bullets under each day's "calendar" section.
/// Changes in Apple Calendar are reflected in the outline; outline changes do NOT push back.
@Observable
@MainActor
final class CalendarSyncEngine {
    static let shared = CalendarSyncEngine()

    private let eventStore = EKEventStore()

    /// Whether the user has granted Calendar access
    var isAuthorized = false

    /// Debounce timer for EKEventStoreChanged notifications
    private var debounceTask: Task<Void, Never>?

    private init() {}

    // MARK: - Authorization

    /// Request access to Apple Calendar. Returns true if granted.
    func requestAccess() async -> Bool {
        if #available(macOS 14.0, iOS 17.0, *) {
            do {
                let granted = try await eventStore.requestFullAccessToEvents()
                isAuthorized = granted
                print("[Calendar] Full access \(granted ? "granted" : "denied")")
                return granted
            } catch {
                print("[Calendar] Authorization error: \(error)")
                isAuthorized = false
                return false
            }
        } else {
            do {
                let granted = try await eventStore.requestAccess(to: .event)
                isAuthorized = granted
                print("[Calendar] Access \(granted ? "granted" : "denied")")
                return granted
            } catch {
                print("[Calendar] Authorization error: \(error)")
                isAuthorized = false
                return false
            }
        }
    }

    // MARK: - Observation

    /// Start observing changes from Apple Calendar (EKEventStoreChanged notification).
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
        print("[Calendar] Started observing EKEventStoreChanged")
    }

    /// Debounced handler for store changes
    private func handleStoreChanged() {
        debounceTask?.cancel()
        debounceTask = Task {
            try? await Task.sleep(nanoseconds: 500_000_000) // 500ms debounce
            guard !Task.isCancelled else { return }
            await syncCalendarEvents()
        }
    }

    // MARK: - Core Sync

    /// Sync calendar events for the current week into the outline.
    /// For each day: fetch events, update/create/remove event nodes under the "calendar" section.
    func syncCalendarEvents() async {
        guard isAuthorized else { return }
        guard let document = WindowManager.shared.document else { return }

        let weekDates = DateStructureManager.shared.currentWeekDates()
        let calendar = Calendar.current
        var didChange = false

        // Get selected calendar IDs (empty = all calendars)
        let selectedIds = SettingsManager.shared.selectedCalendarIds
        let calendars: [EKCalendar]?
        if selectedIds.isEmpty {
            calendars = nil // All calendars
        } else {
            calendars = eventStore.calendars(for: .event).filter { selectedIds.contains($0.calendarIdentifier) }
            if calendars?.isEmpty == true {
                // If all selected calendars are gone, fall back to all
                // (user may have deleted a calendar)
            }
        }

        for date in weekDates {
            let startOfDay = calendar.startOfDay(for: date)
            guard let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay) else { continue }

            // Find the date node
            guard let dateNode = DateStructureManager.shared.dateNode(for: date, in: document) else { continue }

            // Find the "calendar" section
            let calendarSectionId = DateStructureManager.deterministicSectionUUID(for: date, sectionType: "calendar")
            guard let calendarSection = dateNode.children.first(where: { $0.id == calendarSectionId }) else { continue }

            // Fetch events for this day
            let predicate = eventStore.predicateForEvents(withStart: startOfDay, end: endOfDay, calendars: calendars)
            let events = eventStore.events(matching: predicate)
                .sorted { e1, e2 in
                    // All-day events first, then sorted by start time
                    if e1.isAllDay != e2.isAllDay { return e1.isAllDay }
                    return e1.startDate < e2.startDate
                }

            // Build set of current event identifiers
            let currentEventIds = Set(events.map { $0.calendarItemIdentifier })

            // Remove event nodes whose identifier no longer matches any fetched event
            let existingEventNodes = calendarSection.children.filter { $0.isCalendarEvent }
            for eventNode in existingEventNodes {
                guard let eventId = eventNode.calendarEventIdentifier else { continue }
                if !currentEventIds.contains(eventId) {
                    eventNode.removeFromParent()
                    didChange = true
                    print("[Calendar] Removed event node: \(eventNode.title)")
                }
            }

            // Update existing and create new event nodes
            for (sortIdx, event) in events.enumerated() {
                let eventId = event.calendarItemIdentifier
                let formattedTitle = formatEventTitle(event)
                let calName = event.calendar?.title

                if let existingNode = calendarSection.children.first(where: { $0.calendarEventIdentifier == eventId }) {
                    // Update if title or calendar changed
                    if existingNode.title != formattedTitle {
                        existingNode.title = formattedTitle
                        didChange = true
                    }
                    if existingNode.calendarName != calName {
                        existingNode.calendarName = calName
                        didChange = true
                    }
                    existingNode.sortIndex = Int64(sortIdx) * OutlineNode.sortIndexGap
                } else {
                    // Create new event node
                    let newNode = OutlineNode(
                        title: formattedTitle,
                        sortIndex: Int64(sortIdx) * OutlineNode.sortIndexGap,
                        calendarEventIdentifier: eventId,
                        calendarName: calName
                    )
                    // Insert at the correct position (after existing events, sorted by sortIdx)
                    let insertIndex = calendarSection.children.filter({ !$0.isPlaceholder }).count
                    calendarSection.addChild(newNode, at: insertIndex)
                    didChange = true
                    print("[Calendar] Created event node: \(formattedTitle)")
                }
            }

            // Re-sort event nodes by sortIndex
            let nonEventChildren = calendarSection.children.filter { !$0.isCalendarEvent && !$0.isPlaceholder }
            let eventChildren = calendarSection.children.filter { $0.isCalendarEvent }
                .sorted { $0.sortIndex < $1.sortIndex }
            let placeholders = calendarSection.children.filter { $0.isPlaceholder }
            calendarSection.children = eventChildren + nonEventChildren + placeholders
            for child in calendarSection.children {
                child.parent = calendarSection
            }

            // Manage placeholder
            DateStructureManager.shared.ensurePlaceholder(in: calendarSection, date: date, sectionType: "calendar")
        }

        if didChange {
            document.structureVersion += 1
            iCloudManager.shared.scheduleAutoSave(for: document)
            print("[Calendar] Sync complete — changes applied")
        } else {
            print("[Calendar] Sync complete — no changes")
        }
    }

    // MARK: - Event Title Formatting

    /// Format an EKEvent title for display.
    /// All-day: "Title (all day)"
    /// Timed: "Title 9:00 AM - 10:00 AM"
    func formatEventTitle(_ event: EKEvent) -> String {
        let title = event.title ?? "Untitled"

        if event.isAllDay {
            return "\(title) (all day)"
        }

        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"

        let startTime = formatter.string(from: event.startDate)
        let endTime = formatter.string(from: event.endDate)
        return "\(title) \(startTime) - \(endTime)"
    }

    // MARK: - Available Calendars

    /// Returns all available event calendars for the picker UI
    func availableCalendars() -> [EKCalendar] {
        eventStore.calendars(for: .event)
    }
}
