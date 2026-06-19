import SwiftUI

/// The 3D Cover Flow stage. A single `position` value is chased by a spring;
/// every card derives its rotation/offset/depth from that one value, so the
/// motion stays coherent and interruptible — the LP-flip feel.
struct CoverFlowView: View {
    let projects: [Project]
    @Binding var selectedID: Project.ID?
    var metrics: CoverFlowMetrics
    let tick: TickPlayer
    let store: LibraryStore
    var onActivateCenter: (Project) -> Void = { _ in }

    @State private var position: Double = 0
    @State private var dragAnchor: Double? = nil
    @State private var lastDragCenter: Int = 0
    @FocusState private var focused: Bool

    private var selectedIndex: Int? { projects.firstIndex { $0.id == selectedID } }

    private var visibleIndices: [Int] {
        guard !projects.isEmpty else { return [] }
        let center = Int(position.rounded())
        let lo = max(0, center - 9)
        let hi = min(projects.count - 1, center + 9)
        return Array(lo...hi)
    }

    var body: some View {
        ZStack {
            ForEach(visibleIndices, id: \.self) { i in
                let t = CardTransform.compute(index: i, position: position, m: metrics)
                CoverCardView(project: projects[i], metrics: metrics,
                              dim: t.dim, reflectionOpacity: t.reflectionOpacity)
                    .scaleEffect(t.scale)
                    .rotation3DEffect(.degrees(t.angle),
                                      axis: (x: 0, y: 1, z: 0),
                                      anchor: UnitPoint(x: 0.5, y: 0.35),
                                      perspective: 0.55)
                    .offset(x: t.xOffset)
                    .zIndex(t.zIndex)
                    .contentShape(Rectangle())
                    .onTapGesture { tapSelect(i) }
                    .contextMenu { ProjectContextMenu(project: projects[i], store: store) }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
        .gesture(dragGesture)
        .focusable()
        .focused($focused)
        .focusEffectDisabled()
        .onMoveCommand { dir in
            switch dir {
            case .left, .up:    step(-1)
            case .right, .down: step(1)
            default: break
            }
        }
        .onTapGesture { focused = true }
        .onAppear {
            if let idx = selectedIndex { position = Double(idx) }
            DispatchQueue.main.async { focused = true }
        }
        .onChange(of: selectedID) { _, newID in
            // While dragging, the drag handler owns `position` and the ticks —
            // don't spring or double-tick here.
            if dragAnchor != nil { return }
            guard let idx = projects.firstIndex(where: { $0.id == newID }) else { return }
            let target = Double(idx)
            if abs(target - position) > 0.01 {
                tick.play(direction: target >= position ? 1 : -1,
                          velocity: min(1, abs(target - position) * 0.6 + 0.3))
            }
            withAnimation(CoverFlowMetrics.spring) { position = target }
        }
        .onChange(of: projects.map(\.id)) { _, _ in
            // keep position valid if the visible set changed under us
            if let idx = selectedIndex { position = Double(idx) }
        }
    }

    /// Drag-to-flip, mirroring the reference Cover Flow's onDrag/onDragEnd:
    /// position tracks the finger 1:1 (in card units), and on release the
    /// throw velocity is projected to pick a snap target.
    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 6)
            .onChanged { value in
                if dragAnchor == nil {
                    dragAnchor = position
                    lastDragCenter = clampedIndex(position)
                    focused = true
                }
                let pxPerCard = Double(metrics.centerGap * 0.8)
                let raw = (dragAnchor ?? position) - Double(value.translation.width) / pxPerCard
                position = min(max(raw, 0), Double(max(projects.count - 1, 0)))

                // Tick + commit selection each time a new cover reaches centre,
                // so a fast drag rattles "drr-drr-drr" like holding the arrow key.
                let center = clampedIndex(position)
                if center != lastDragCenter {
                    let dir = center > lastDragCenter ? 1 : -1
                    lastDragCenter = center
                    let speed = Double(abs(value.velocity.width))
                    tick.play(direction: dir, velocity: min(1.0, speed / 2500.0 + 0.25))
                    selectedID = projects[center].id   // live follow (onChange is guarded mid-drag)
                }
            }
            .onEnded { value in
                let pxPerCard = Double(metrics.centerGap * 0.8)
                let anchor = dragAnchor ?? position
                let projected = anchor - Double(value.predictedEndTranslation.width) / pxPerCard
                let target = max(0, min(projects.count - 1, Int(projected.rounded())))
                dragAnchor = nil
                guard projects.indices.contains(target) else { return }
                let id = projects[target].id
                if id == selectedID {
                    // Selection didn't change → settle the position ourselves.
                    withAnimation(CoverFlowMetrics.spring) { position = Double(target) }
                } else {
                    selectedID = id   // onChange(selectedID) springs + ticks
                }
            }
    }

    private func step(_ delta: Int) {
        guard !projects.isEmpty else { return }
        guard let idx = selectedIndex else {
            selectedID = projects.first?.id
            return
        }
        let next = max(0, min(projects.count - 1, idx + delta))
        if next != idx { selectedID = projects[next].id }
    }

    private func tapSelect(_ i: Int) {
        guard projects.indices.contains(i) else { return }
        if i == selectedIndex {
            // Clicking the already-centred cover offers the launchers.
            onActivateCenter(projects[i])
        } else {
            selectedID = projects[i].id
            focused = true
        }
    }

    private func clampedIndex(_ p: Double) -> Int {
        guard !projects.isEmpty else { return 0 }
        return max(0, min(projects.count - 1, Int(p.rounded())))
    }
}
