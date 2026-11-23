import AppKit
import Combine
import SwiftUI

@MainActor
final class IslandController {
    private let viewModel = IslandViewModel()
    private var panel: NotchPanel?
    private var monitors: [Any] = []
    private var collapseWorkItem: DispatchWorkItem?
    private var alertTimer: Timer?
    /// Matches `NotchPanel`'s initial state; see `setPanelIgnoresMouse`.
    private var panelIgnoresMouse = true
    private var cursorTimer: Timer?
    private var cursorPollInterval: TimeInterval = 0
    private var wakeObserver: NSObjectProtocol?
    private var cancellables: Set<AnyCancellable> = []
    /// Events (`DayEvent.id`) whose alert the user closed; they stay silent until their window ends.
    private var dismissedAlertIDs: Set<String> = []
    /// Events the sound was already played for.
    private var announcedAlertIDs: Set<String> = []
    /// Accessories whose low-battery warning the user closed; they stay silent until charged.
    private var dismissedBatteryIDs: Set<String> = []
    private var alertSound: NSSound?
    /// Last laid-out island size, so only a real change relays out the panel.
    private var lastExpandedSize: CGSize = .zero

    private static let alertSoundName = "Glass"
    /// Re-check interval while an alert is on screen.
    private static let alertTickInterval: TimeInterval = 1
    /// Cursor poll while it is nowhere near the island.
    private static let farPollInterval: TimeInterval = 0.5
    /// Cursor poll near the top of the island's screen, where a late hover would show.
    private static let nearPollInterval: TimeInterval = 0.05
    /// Band at the top of that screen counted as near. Sized against `farPollInterval`: a cursor has to
    /// outrun it to land on the island while the slow rate is still in effect, which would hold the
    /// hover back by one slow tick.
    private static let nearBand: CGFloat = 600
    private static let alertSoundDuration: TimeInterval = 2

    /// Extra transparent space around the expanded island so the shadow is not clipped.
    private let shadowPadding: CGFloat = 60

    private let expandAnimation = Animation.spring(response: 0.42, dampingFraction: 0.74)
    private let collapseAnimation = Animation.spring(response: 0.36, dampingFraction: 0.88)
    private let hoverAnimation = Animation.spring(response: 0.3, dampingFraction: 0.65)
    private let weatherAnimation = Animation.spring(response: 0.4, dampingFraction: 0.82)
    private let alertAnimation = Animation.spring(response: 0.45, dampingFraction: 0.8)

    func start() {
        viewModel.onOpenSettings = { [weak self] in
            self?.collapse()
            SettingsWindowController.shared.show()
        }
        viewModel.onCollapseRequest = { [weak self] in self?.collapse() }
        viewModel.onDismissEventAlert = { [weak self] in self?.dismissEventAlert() }
        viewModel.onDismissBatteryAlert = { [weak self] in self?.dismissBatteryAlert() }
        viewModel.onWeatherToggle = { [weak self] in
            guard let self else { return }
            withAnimation(self.weatherAnimation) { self.viewModel.isWeatherExpanded.toggle() }
        }
        viewModel.onKeepAwakePickerToggle = { [weak self] in
            guard let self else { return }
            withAnimation(self.weatherAnimation) { self.viewModel.isKeepAwakePickerOpen.toggle() }
        }

        let panel = NotchPanel(contentRect: .zero)
        let host = FirstMouseHostingView(rootView: IslandRootView(viewModel: viewModel, onTap: { [weak self] in
            self?.expand()
        }))
        host.sizingOptions = []
        panel.contentView = host
        self.panel = panel

        layout()
        panel.orderFrontRegardless()

        installMonitors()
        startGeometryWatch()
        startEventAlerts()
        startBatteryAlerts()

        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.layout() }
        }
    }

    // MARK: - Layout

    /// The top-row slider and the number of accessories both change the expanded island's size,
    /// so the panel is laid out again whenever it differs from the one in place.
    private func startGeometryWatch() {
        NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in MainActor.assumeIsolated { self?.syncGeometry() } }
            .store(in: &cancellables)
        DeviceBatteryStore.shared.$devices
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in MainActor.assumeIsolated { self?.syncGeometry() } }
            .store(in: &cancellables)
    }

    private func syncGeometry() {
        guard viewModel.maxExpandedSize != lastExpandedSize else { return }
        viewModel.objectWillChange.send()
        layout()
    }

    private func layout() {
        guard let panel else { return }
        viewModel.notch = NotchGeometry.detect()
        let expanded = viewModel.maxExpandedSize
        lastExpandedSize = expanded
        let width = expanded.width + shadowPadding * 2
        let height = expanded.height + shadowPadding
        let frame = NSRect(
            x: viewModel.notch.midX - width / 2,
            y: viewModel.notch.screenFrame.maxY - height,
            width: width,
            height: height
        )
        panel.setFrame(frame, display: true)
    }

    // MARK: - Event alert

    private func startEventAlerts() {
        CalendarStore.shared.$schedule
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in MainActor.assumeIsolated { self?.updateEventAlert() } }
            .store(in: &cancellables)
        NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in MainActor.assumeIsolated { self?.updateEventAlert() } }
            .store(in: &cancellables)

        // A timer that slept through a system sleep fires late, so the state is re-read on wake.
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.updateEventAlert() }
        }

        updateEventAlert()
    }

    /// Next moment the alert can change on its own: an event entering its lead window, or the current
    /// one leaving its trail. Nil when the schedule holds nothing else.
    private func nextAlertEdge(now: Date) -> Date? {
        let lead = TimeInterval(max(AppSettings.eventAlertLead, 0) * 60)
        let trail = TimeInterval(max(AppSettings.eventAlertTrail, 0) * 60)
        return CalendarStore.shared.schedule
            .filter { !$0.isAllDay }
            .flatMap { [$0.start.addingTimeInterval(-lead), $0.start.addingTimeInterval(trail)] }
            .filter { $0 > now }
            .min()
    }

    /// While an alert is up the island re-checks every second, because the window closes on a whole
    /// second and the countdown has to end with it. The rest of the time a single timer is armed for the
    /// next window edge instead, so an idle Mac is not woken 86 400 times a day for a check that changes
    /// nothing. The schedule and the settings reach `updateEventAlert()` through their own publishers.
    private func rescheduleAlertTimer(now: Date, alertActive: Bool) {
        alertTimer?.invalidate()
        alertTimer = nil

        let fire: Date
        let tolerance: TimeInterval
        if alertActive {
            fire = now.addingTimeInterval(Self.alertTickInterval)
            tolerance = 0.2
        } else if let edge = nextAlertEdge(now: now) {
            fire = edge
            tolerance = 0.5
        } else {
            return
        }

        let timer = Timer(fire: fire, interval: 0, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.updateEventAlert() }
        }
        timer.tolerance = tolerance
        RunLoop.main.add(timer, forMode: .common)
        alertTimer = timer
    }

    /// Timed schedule events within [start − lead, start + trail).
    private func alertWindowEvents(now: Date = Date()) -> [DayEvent] {
        let lead = TimeInterval(max(AppSettings.eventAlertLead, 0) * 60)
        let trail = TimeInterval(max(AppSettings.eventAlertTrail, 0) * 60)
        return CalendarStore.shared.schedule.filter { event in
            !event.isAllDay
                && event.start.addingTimeInterval(-lead) <= now
                && now < event.start.addingTimeInterval(trail)
        }
    }

    private func eventsInAlertWindow() -> Set<String> {
        Set(alertWindowEvents().map(\.id))
    }

    private func updateEventAlert() {
        let now = Date()
        let windowEvents = alertWindowEvents(now: now)
        let inWindow = Set(windowEvents.map(\.id))
        dismissedAlertIDs.formIntersection(inWindow)
        announcedAlertIDs.formIntersection(inWindow)

        let pending = inWindow.subtracting(dismissedAlertIDs)
        if !pending.isSubset(of: announcedAlertIDs) {
            announcedAlertIDs.formUnion(pending)
            playAlertSound()
        }

        // Count down to the nearest upcoming event; once all have started, show the latest started one.
        let pendingEvents = windowEvents.filter { pending.contains($0.id) }
        let upcoming = pendingEvents.filter { $0.start > now }.map(\.start).min()
        let target = upcoming ?? pendingEvents.map(\.start).max()
        if viewModel.eventAlertStart != target { viewModel.eventAlertStart = target }

        let active = !pending.isEmpty
        rescheduleAlertTimer(now: now, alertActive: active)

        guard active != viewModel.hasEventAlert else { return }
        withAnimation(alertAnimation) { viewModel.hasEventAlert = active }
        handleMouseMove()
    }

    /// Closes the current alert; the next event raises a new one.
    private func dismissEventAlert() {
        dismissedAlertIDs.formUnion(eventsInAlertWindow())
        stopAlertSound()
        updateEventAlert()
    }

    /// One short chime, cut off after a couple of seconds.
    private func playAlertSound() {
        guard AppSettings.eventAlertSound, let sound = NSSound(named: Self.alertSoundName) else { return }
        alertSound?.stop()
        sound.volume = 0.6
        sound.play()
        alertSound = sound
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.alertSoundDuration) { [weak self] in
            MainActor.assumeIsolated {
                guard self?.alertSound === sound else { return }
                self?.stopAlertSound()
            }
        }
    }

    private func stopAlertSound() {
        alertSound?.stop()
        alertSound = nil
    }

    // MARK: - Low battery alert

    private func startBatteryAlerts() {
        DeviceBatteryStore.shared.$devices
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in MainActor.assumeIsolated { self?.updateBatteryAlert() } }
            .store(in: &cancellables)
        NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in MainActor.assumeIsolated { self?.updateBatteryAlert() } }
            .store(in: &cancellables)
        updateBatteryAlert()
    }

    /// The warning stays up while the device is low and off the charger; once it charges it drops out of
    /// `draining`, which also clears the dismissal so a later drain warns again.
    private func updateBatteryAlert() {
        let draining = AppSettings.lowBatteryAlert
            ? DeviceBatteryStore.shared.devices.filter(\.needsCharging)
            : []
        dismissedBatteryIDs.formIntersection(Set(draining.map(\.id)))

        let target = draining
            .filter { !dismissedBatteryIDs.contains($0.id) }
            .min { $0.percent < $1.percent }
        guard viewModel.batteryAlert != target else { return }
        withAnimation(alertAnimation) { viewModel.batteryAlert = target }
        handleMouseMove()
    }

    /// Hides the warning for this device until it is charged and runs low again.
    private func dismissBatteryAlert() {
        guard let current = viewModel.batteryAlert else { return }
        dismissedBatteryIDs.insert(current.id)
        updateBatteryAlert()
    }

    // MARK: - Mouse tracking

    private func installMonitors() {
        // Mouse moves are polled rather than monitored: a monitor is woken by every move anywhere on
        // screen, a few hundred times a second, while the island only needs to know where the cursor
        // is right now. Clicks are rare, so those stay on a monitor.
        startCursorPoll(interval: Self.farPollInterval)

        // Clicks outside our window arrive only through the global monitor.
        if let clicks = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown], handler: { [weak self] _ in
            MainActor.assumeIsolated { self?.handleOutsideClick() }
        }) {
            monitors.append(clicks)
        }
    }

    /// Mirror of the panel's `ignoresMouseEvents`. Writing that property is a round trip to the window
    /// server, and a mouse move arrives a few hundred times a second, so it is only written on a real flip.
    private func setPanelIgnoresMouse(_ ignores: Bool) {
        guard ignores != panelIgnoresMouse else { return }
        panelIgnoresMouse = ignores
        panel?.ignoresMouseEvents = ignores
    }

    /// Runs the timer at `interval`, leaving it alone when it is already the one in place.
    private func startCursorPoll(interval: TimeInterval) {
        guard cursorPollInterval != interval else { return }
        cursorTimer?.invalidate()
        cursorPollInterval = interval

        let timer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.pollCursor() }
        }
        timer.tolerance = interval / 4
        // Menus and drags run their own run loop modes; the island has to keep up through those too.
        RunLoop.main.add(timer, forMode: .common)
        cursorTimer = timer
    }

    /// Reads the cursor, then picks the rate for the next reads: fast near the island, slow elsewhere.
    private func pollCursor() {
        // Read once and pass it on: `NSEvent.mouseLocation` is a round trip to the window server,
        // and at poll rates that is the bulk of what the island costs while idle.
        let location = NSEvent.mouseLocation
        handleMouseMove(location: location)

        let screen = viewModel.notch.screenFrame
        let near = viewModel.isExpanded
            || (location.x >= screen.minX && location.x <= screen.maxX
                && location.y >= screen.maxY - Self.nearBand)
        startCursorPoll(interval: near ? Self.nearPollInterval : Self.farPollInterval)
    }

    /// `location` defaults to a fresh reading for the callers that have none at hand; the cursor poll
    /// passes the one it already read.
    private func handleMouseMove(location: NSPoint = NSEvent.mouseLocation) {
        let inside = viewModel.hitRect.contains(location)
        setPanelIgnoresMouse(!inside)

        switch viewModel.state {
        case .collapsed:
            if inside != viewModel.isHovering {
                withAnimation(hoverAnimation) { viewModel.isHovering = inside }
            }
        case .expanded:
            // The expanded weather block shrinks back once the cursor leaves it.
            if viewModel.isWeatherExpanded,
               !viewModel.weatherScreenRect.insetBy(dx: -4, dy: -4).contains(location) {
                withAnimation(weatherAnimation) { viewModel.isWeatherExpanded = false }
            }
            if inside {
                cancelScheduledCollapse()
            } else if AppSettings.collapseOnMouseExit {
                scheduleCollapse()
            }
        }
    }

    private func handleOutsideClick() {
        guard viewModel.isExpanded, !viewModel.hitRect.contains(NSEvent.mouseLocation) else { return }
        collapse()
    }

    // MARK: - State transitions

    private func expand() {
        guard !viewModel.isExpanded else { return }
        cancelScheduledCollapse()
        if AppSettings.hapticFeedback {
            NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .now)
        }
        withAnimation(expandAnimation) {
            viewModel.state = .expanded
            viewModel.isHovering = false
        }
        setPanelIgnoresMouse(false)
    }

    private func collapse() {
        cancelScheduledCollapse()
        guard viewModel.isExpanded else { return }
        withAnimation(collapseAnimation) {
            viewModel.state = .collapsed
            viewModel.isHovering = false
            viewModel.isWeatherExpanded = false
            viewModel.isKeepAwakePickerOpen = false
        }
        handleMouseMove()
    }

    private func scheduleCollapse() {
        guard collapseWorkItem == nil else { return }
        let item = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated {
                self?.collapseWorkItem = nil
                self?.collapse()
            }
        }
        collapseWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6, execute: item)
    }

    private func cancelScheduledCollapse() {
        collapseWorkItem?.cancel()
        collapseWorkItem = nil
    }
}
