import SwiftUI

struct ContentView: View {
    @State private var model = MapState()
    @State private var retainedDetail: [MapNode] = []
    @State private var previousDrag = CGSize.zero
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 0) {
            header
            GeometryReader { geometry in
                MapDrawing(scale: model.camera.scale, offset: model.camera.offset,
                           progress: model.progress, overview: model.overviewNodes,
                           detail: retainedDetail, hoveredID: model.hoveredID)
                    .accessibilityHidden(true)
                    .overlay {
                        ZStack(alignment: .topLeading) {
                            ForEach(model.activeNodes) { node in
                                let center = model.camera.screen(node.center)
                                Group {
                                    if node.isRoot || model.showingDetail {
                                        Color.clear
                                            .accessibilityElement()
                                            .accessibilityLabel(node.title)
                                            .accessibilityAddTraits(.isStaticText)
                                            .accessibilityIdentifier("topic-\(node.id)")
                                            .allowsHitTesting(false)
                                    } else {
                                        Button { enter(node.id) } label: {
                                            Color.clear.contentShape(Rectangle())
                                        }
                                        .buttonStyle(.plain)
                                        .accessibilityLabel(node.title)
                                        .accessibilityIdentifier("branch-\(node.id)")
                                        .accessibilityHint("Explore subbranches")
                                    }
                                }
                                .frame(width: node.bounds.width * model.camera.scale,
                                       height: node.bounds.height * model.camera.scale)
                                .position(center)
                            }
                        }
                        .frame(width: geometry.size.width, height: geometry.size.height)
                    }
                    .background(.background)
                    .contentShape(Rectangle())
                    .clipped()
                    .onContinuousHover(coordinateSpace: .local) { phase in
                        switch phase {
                        case .active(let point): model.hover(at: point)
                        case .ended: model.hover(at: nil)
                        }
                    }
                    .gesture(DragGesture(minimumDistance: 3, coordinateSpace: .local)
                        .onChanged { value in
                            model.pan(by: CGSize(width: value.translation.width - previousDrag.width,
                                                 height: value.translation.height - previousDrag.height))
                            previousDrag = value.translation
                        }
                        .onEnded { _ in previousDrag = .zero })
                    .onTapGesture(count: 2, coordinateSpace: .local) { point in
                        guard model.focus == nil,
                              let node = MapLayout.hit(at: point, camera: model.camera, nodes: model.overviewNodes),
                              !node.isRoot else { return }
                        enter(node.id)
                    }
                    .background {
                        #if os(macOS)
                        CanvasInput(onZoom: { factor, point in
                            model.zoom(factor: factor, at: point)
                            retainDetail()
                        }, onPan: model.pan)
                        #endif
                    }
                    .onAppear { model.resize(geometry.size) }
                    .onChange(of: geometry.size) { _, size in model.resize(size) }
            }
            footer
        }
        .frame(minWidth: 420, minHeight: 420)
        #if os(macOS)
        .onExitCommand { navigate { model.back() } }
        #endif
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "point.3.connected.trianglepath.dotted")
                .font(.title2).foregroundStyle(.teal)
            VStack(alignment: .leading, spacing: 3) {
                Text("LangMap").font(.headline)
                Text("German grammar").font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            HStack(spacing: 8) {
                Button("German") { navigate { model.back() } }
                    .buttonStyle(.plain)
                    .keyboardShortcut(.cancelAction)
                    .foregroundStyle(model.focus == nil ? Color.primary : .accentColor)
                    .accessibilityIdentifier("overview")
                if let focus = model.focus {
                    Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.tertiary)
                    Text(focus.branch.title).fontWeight(.medium)
                        .accessibilityIdentifier("focused-branch")
                }
            }
            .font(.subheadline)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 18)
        .background(.bar)
    }

    private var footer: some View {
        HStack(spacing: 16) {
            Text(model.focus == nil ? "Drag to pan · Pinch or ⌘-scroll to zoom" : "Zoom out to return · Drag to explore")
                .font(.caption).foregroundStyle(.secondary)
                .lineLimit(2)
            Spacer(minLength: 4)
            HStack(spacing: 12) {
                Button { zoom(1 / 1.2) } label: { Image(systemName: "minus").frame(width: 24, height: 24) }
                    .accessibilityLabel("Zoom out")
                    .keyboardShortcut("-", modifiers: .command)
                Text("\(model.zoomPercent)%")
                    .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                    .frame(width: 45)
                    .accessibilityIdentifier("zoom-percent")
                Button { zoom(1.2) } label: { Image(systemName: "plus").frame(width: 24, height: 24) }
                    .accessibilityLabel("Zoom in")
                    .keyboardShortcut("=", modifiers: .command)
            }
            .buttonStyle(.borderless)
            Divider().frame(height: 18)
            Button { navigate { model.reset() } } label: {
                Image(systemName: "arrow.up.left.and.arrow.down.right")
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("Reset view")
            .help("Reset view")
            .keyboardShortcut("0", modifiers: .command)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 14)
        .background(.bar)
    }

    private func retainDetail() {
        if model.focus != nil { retainedDetail = model.detailNodes }
    }

    private func enter(_ id: String) {
        // Capture the new scene before animating its opacity from zero.
        navigate { model.enter(branchID: id) }
        retainDetail()
    }

    private func zoom(_ factor: CGFloat) {
        model.zoom(factor: factor, at: model.viewportCenter)
        retainDetail()
    }

    private func navigate(_ action: () -> Void) {
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.28), action)
    }
}

#Preview { ContentView() }
