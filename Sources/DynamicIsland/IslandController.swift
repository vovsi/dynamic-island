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
    private var cancellables: Set<AnyCancellable> = []
    /// Events (`DayEvent.id`) whose alert the user closed; they stay silent until their window ends.
    private var dismissedAlertIDs: Set<String> = []
    /// Events the sound was already played for.
    private var announcedAlertIDs: Set<String> = []
    private var alertSound: NSSound?

    private static let alertSoundName = "Glass"
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
        viewModel.onWeatherToggle = { [weak self] in
            guard let self else { return }
            withAnimation(self.weatherAnimation) { self.viewModel.isWeatherExpanded.toggle() }
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
        startEventAlerts()

        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.layout() }
        }
    }

    // MARK: - Layout

    private func layout() {
        guard let panel else { return }
        viewModel.notch = NotchGeometry.detect()
        let expanded = viewModel.maxExpandedSize
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

        let timer = Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.updateEventAlert() }
        }
        timer.tolerance = 2
        alertTimer = timer
        updateEventAlert()
    }

    /// IDs of timed schedule events within [start − lead, start + trail).
    private func eventsInAlertWindow() -> Set<String> {
        let now = Date()
        let lead = TimeInterval(max(AppSettings.eventAlertLead, 0) * 60)
        let trail = TimeInterval(max(AppSettings.eventAlertTrail, 0) * 60)
        return Set(CalendarStore.shared.schedule.filter { event in
            !event.isAllDay
                && event.start.addingTimeInterval(-lead) <= now
                && now < event.start.addingTimeInterval(trail)
        }.map(\.id))
    }

    private func updateEventAlert() {
        let inWindow = eventsInAlertWindow()
        dismissedAlertIDs.formIntersection(inWindow)
        announcedAlertIDs.formIntersection(inWindow)

        let pending = inWindow.subtracting(dismissedAlertIDs)
        if !pending.isSubset(of: announcedAlertIDs) {
            announcedAlertIDs.formUnion(pending)
            playAlertSound()
        }

        let active = !pending.isEmpty
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

    // MARK: - Mouse tracking

    private func installMonitors() {
        let moveMask: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDragged]

        if let global = NSEvent.addGlobalMonitorForEvents(matching: moveMask, handler: { [weak self] _ in
            MainActor.assumeIsolated { self?.handleMouseMove() }
        }) {
            monitors.append(global)
        }

        if let local = NSEvent.addLocalMonitorForEvents(matching: moveMask, handler: { [weak self] event in
            MainActor.assumeIsolated { self?.handleMouseMove() }
            return event
        }) {
            monitors.append(local)
        }

        // Clicks outside our window arrive only through the global monitor.
        if let clicks = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown], handler: { [weak self] _ in
            MainActor.assumeIsolated { self?.handleOutsideClick() }
        }) {
            monitors.append(clicks)
        }
    }

    private func handleMouseMove() {
        let inside = viewModel.hitRect.contains(NSEvent.mouseLocation)
        panel?.ignoresMouseEvents = !inside

        switch viewModel.state {
        case .collapsed:
            if inside != viewModel.isHovering {
                withAnimation(hoverAnimation) { viewModel.isHovering = inside }
            }
        case .expanded:
            // The expanded weather block shrinks back once the cursor leaves it.
            if viewModel.isWeatherExpanded,
               !viewModel.weatherScreenRect.insetBy(dx: -4, dy: -4).contains(NSEvent.mouseLocation) {
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
        panel?.ignoresMouseEvents = false
    }

    private func collapse() {
        cancelScheduledCollapse()
        guard viewModel.isExpanded else { return }
        withAnimation(collapseAnimation) {
            viewModel.state = .collapsed
            viewModel.isHovering = false
            viewModel.isWeatherExpanded = false
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
