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
            TransientLineView(line: line)
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
/// and how its turn or its pipeline ended.
private struct TransientLineView: View {
    let line: TransientLine

    private var isFailure: Bool { line.kind == .failed || line.kind == .ciFailed }

    private var ending: String {
        switch line.kind {
        case .finished: "finished"
        case .failed: "failed"
        case .ciPassed: "CI passed"
        case .ciFailed: "CI failed"
        }
    }

    var body: some View {
        HStack(spacing: 8) {
            StateMark(state: isFailure ? .failed : .finishedTurn).frame(width: 14)
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
