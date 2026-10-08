import AppKit
import Combine
import SessionCore
import SwiftUI

/// The line that tells of a turn or a pipeline that ended: the island grows by one row for a few seconds and
/// collapses by itself. Display only: it never takes clicks or focus, and it gives way to the
/// request card and the session list at once.
@MainActor
final class TransientLineController {
    private static let showFor: TimeInterval = 4

    private let panel: NSPanel
    private let model: AppModel
    private let presence: IslandPresence
    private let stage = IslandStage()
    private let sizer = IslandWindowSizer()
    private var subscriptions: Set<AnyCancellable> = []
    private var observers: [NSObjectProtocol] = []
    /// Collapses the line when its time is up, then takes its window away.
    private var leaving: DispatchWorkItem?

    init(model: AppModel, presence: IslandPresence) {
        self.model = model
        self.presence = presence
        panel = NSPanel(
            contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 2)
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.isMovable = false
        panel.hidesOnDeactivate = false
        panel.appearance = NSAppearance(named: .darkAqua)

        stage.onOpenSizeChange = { [weak self] in self?.fitWindow() }
        model.lines.receive(on: DispatchQueue.main).sink { [weak self] in self?.show($0) }.store(in: &subscriptions)
        // Whatever else opens under the notch has the place.
        presence.$cardIsOpen.merge(with: presence.$listIsOpen).sink { [weak self] isOpen in
            if isOpen { self?.remove() }
        }.store(in: &subscriptions)
        observers = IslandScreen.observe { [weak self] in self?.remove() }
    }

    private func show(_ line: TransientLine) {
        guard !presence.cardIsOpen, !presence.listIsOpen, model.snapshot.raised.isEmpty, let screen = NSScreen.island
        else { return }
        leaving?.cancel()
        let geometry = NotchGeometry(screen: screen)
        let width = geometry.frame.width + Island.lineGrowth
        let content = AnyView(IslandSurface(
            model: model, stage: stage, presence: presence, geometry: geometry, width: width, maxHeight: Island.maxHeight
        ) {
            // A new line each time, so that its mark is drawn anew.
            TransientLineView(line: line).id(UUID())
        })
        if let hosting = panel.contentView as? NSHostingView<AnyView> {
            hosting.rootView = content
        } else {
            let hosting = NSHostingView(rootView: content)
            // The window has the size it is given; left to itself the hosting view would resize it.
            hosting.sizingOptions = []
            panel.contentView = hosting
            sizer.fit(panel, to: CGSize(width: width, height: geometry.frame.height + Island.lineHeight), geometry: geometry, on: screen.frame)
        }
        presence.lineIsOpen = true
        panel.orderFrontRegardless()
        // Once the collapsed shape is on screen, so that there is something to grow from.
        DispatchQueue.main.async { [weak self] in
            guard let self, self.presence.lineIsOpen else { return }
            self.stage.isOpen = true
        }
        schedule(after: Self.showFor) { controller in
            controller.stage.isOpen = false
            controller.schedule(after: Island.closeDuration) { $0.remove() }
        }
    }

    private func schedule(after delay: TimeInterval, _ action: @escaping @MainActor (TransientLineController) -> Void) {
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated {
                guard let self else { return }
                action(self)
            }
        }
        leaving = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    private func fitWindow() {
        guard panel.contentView != nil, let screen = NSScreen.island else { return }
        sizer.fit(panel, to: stage.openSize, geometry: NotchGeometry(screen: screen), on: screen.frame)
    }

    private func remove() {
        leaving?.cancel()
        leaving = nil
        guard presence.lineIsOpen else { return }
        stage.isOpen = false
        panel.orderOut(nil)
        panel.contentView = nil
        presence.lineIsOpen = false
    }
}

/// "frontoffice finished", "frontoffice CI failed": the session by the name the list gives it,
/// and how its turn or its pipeline ended. Or a merge request, by its number and title, and what
/// it waits for.
private struct TransientLineView: View {
    let line: TransientLine

    private var isFailure: Bool {
        switch line.kind {
        case .failed, .ciFailed, .failedAfterMerge: true
        case .finished, .ciPassed, .readyToMerge, .heldAtManualStep: false
        }
    }

    private var ending: String {
        switch line.kind {
        case .finished: "finished"
        case .failed: "failed"
        case .ciPassed: "CI passed"
        case .ciFailed: "CI failed"
        case .readyToMerge: "ready to merge"
        case .failedAfterMerge(let environment):
            environment.map { "deploy to \($0) failed" } ?? "failed after the merge"
        case .heldAtManualStep: "waits to be started"
        }
    }

    var body: some View {
        HStack(spacing: 8) {
            Group {
                if isFailure {
                    StateMark(state: .failed)
                } else if line.kind == .heldAtManualStep {
                    // Nothing ended: somebody is waited for.
                    StateMark(state: .waitingForPermission)
                } else {
                    DrawnCheck()
                }
            }
            .frame(width: 14)
            Text(line.title ?? line.project ?? "Untitled session")
                .font(Island.bodyMedium)
                .foregroundStyle(Island.text)
            Text(ending)
                .font(Island.body)
                .foregroundStyle(isFailure ? Island.failedText : Island.text2)
                .layoutPriority(1)
            Spacer(minLength: 0)
            if line.title != nil, let project = line.project {
                Text(project).font(Island.small).foregroundStyle(Island.text3)
            }
        }
        .lineLimit(1)
        .truncationMode(.tail)
        .padding(.horizontal, Island.openPadding)
        .frame(height: Island.lineHeight)
        .accessibilityElement(children: .combine)
    }
}

/// The mark of something that ended well, drawn as the line appears: the check is written in
/// one stroke while a soft ring spreads from it and fades. Still for those who asked for less motion.
private struct DrawnCheck: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// The ring is in place, about to spread.
    @State private var isPrimed = false
    @State private var isDrawn = false

    /// When the line's content has come into view.
    private static let delay = Island.contentDelay + 0.12

    var body: some View {
        let isDrawn = isDrawn || reduceMotion
        Check()
            .trim(from: 0, to: isDrawn ? 1 : 0)
            .stroke(Island.finished, style: StrokeStyle(lineWidth: 1.6, lineCap: .round, lineJoin: .round))
            .frame(width: 9, height: 8)
            .scaleEffect(isDrawn ? 1 : 0.7)
            .background {
                Circle()
                    .stroke(Island.finished, lineWidth: 1)
                    .frame(width: 10, height: 10)
                    .scaleEffect(isDrawn ? 2.4 : 0.5)
                    .opacity(isPrimed && !isDrawn ? 0.7 : 0)
            }
            .task {
                guard !reduceMotion else { return }
                try? await Task.sleep(for: .seconds(Self.delay))
                isPrimed = true
                // A frame with the ring in place, for it to spread from.
                try? await Task.sleep(for: .milliseconds(20))
                withAnimation(.spring(response: 0.38, dampingFraction: 0.62)) { self.isDrawn = true }
            }
    }

    /// The check of `StateMark`, as one stroke from its short arm to its long one.
    private struct Check: Shape {
        func path(in rect: CGRect) -> Path {
            var path = Path()
            path.move(to: CGPoint(x: rect.minX + 0.11 * rect.width, y: rect.minY + 0.525 * rect.height))
            path.addLine(to: CGPoint(x: rect.minX + 0.38 * rect.width, y: rect.minY + 0.81 * rect.height))
            path.addLine(to: CGPoint(x: rect.minX + 0.89 * rect.width, y: rect.minY + 0.19 * rect.height))
            return path
        }
    }
}
