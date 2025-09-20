import SwiftUI

/// View-model for the Map Editor screen.
/// - Holds the editable `map`
/// - Exposes zoom/offset for panning
/// - Computes smooth contours for preview
final class MapEditorViewModel: ObservableObject {

    // MARK: Published state
    @Published var map: Map2D
    @Published var zoom: CGFloat = 1.0
    @Published var offset: CGSize = .zero
    @Published private(set) var contours: [[Point]] = []

    // MARK: Init
    init(map: Map2D) {
        self.map = map
        recomputeContours()
    }

    // MARK: Derived metrics
    func cellSize(in size: CGSize) -> CGFloat {
        min(size.width / CGFloat(map.spec.width),
            size.height / CGFloat(map.spec.height)) * zoom
    }

    // Convert world XZ (meters) ↔︎ view space (points)
    func toView(_ worldXZ: SIMD2<Float>, size: CGSize) -> CGPoint {
        let s = cellSize(in: size)
        let gx = (CGFloat((worldXZ.x - map.spec.originWorldXZ.x) / map.spec.resolution) + 0.5) * s
        let gy = (CGFloat((worldXZ.y - map.spec.originWorldXZ.y) / map.spec.resolution) + 0.5) * s
        return CGPoint(x: gx + offset.width, y: gy + offset.height)
    }

    func toWorld(_ pt: CGPoint, size: CGSize) -> SIMD2<Float> {
        let s = cellSize(in: size)
        let gx = (Float((pt.x - offset.width)/s) - 0.5) * map.spec.resolution + map.spec.originWorldXZ.x
        let gy = (Float((pt.y - offset.height)/s) - 0.5) * map.spec.resolution + map.spec.originWorldXZ.y
        return SIMD2(gx, gy)
    }

    // MARK: Mutations
    func addBeacon(at worldXZ: SIMD2<Float>, name: String? = nil) {
        let n = name ?? "Beacon \(map.beacons.count + 1)"
        map.beacons.append(.init(position: worldXZ, name: n))
        recomputeContoursIfNeeded()
    }

    func addDoorway(a: SIMD2<Float>, b: SIMD2<Float>, width: Float = 0.9) {
        let d = Doorway(a: a, b: b, width: max(0.4, width))
        map.doorways.append(d)
        // Optional: carve corridor visually in editor if desired.
        recomputeContoursIfNeeded()
    }

    // MARK: Contours
    /// Public method you can call from the view to refresh the smooth outline.
    func recomputeContours() {
        contours = ContourPipeline.smoothContours(from: map)
    }

    private func recomputeContoursIfNeeded() {
        // Currently always recompute; you can debounce if needed.
        recomputeContours()
    }
}


/// Map Editor screen (canvas + simple controls)
struct MapEditorView: View {
    @ObservedObject var vm: MapEditorViewModel
    let onSave: (Map2D) -> Void

    var body: some View {
        GeometryReader { geo in
            Canvas { ctx, size in
                let s = vm.cellSize(in: size)
                ctx.translateBy(x: vm.offset.width, y: vm.offset.height)

                // Walls
                for y in 0..<vm.map.spec.height {
                    for x in 0..<vm.map.spec.width {
                        if vm.map.grid[vm.map.idx(x, y)] == .wall {
                            let r = CGRect(x: CGFloat(x)*s, y: CGFloat(y)*s, width: s, height: s)
                            ctx.fill(Path(r), with: .color(.black.opacity(0.85)))
                        }
                    }
                }

                // Doorways
                for d in vm.map.doorways {
                    let a = vm.toView(d.a, size: size); let b = vm.toView(d.b, size: size)
                    var p = Path(); p.move(to: a); p.addLine(to: b)
                    ctx.stroke(p, with: .color(.blue), lineWidth: max(2, s * 0.2))
                }

                // Beacons
                for b in vm.map.beacons {
                    let p = vm.toView(b.position, size: size)
                    let r = max(5, s * 0.35)
                    ctx.fill(Path(ellipseIn: CGRect(x: p.x - r, y: p.y - r, width: r*2, height: r*2)),
                             with: .color(.green))
                }

                // (Optional) If you want to preview smooth contours in the editor:
                // for poly in vm.contours {
                //     var path = Path()
                //     guard let first = poly.first else { continue }
                //     let toPt: (Point) -> CGPoint = { q in
                //         CGPoint(x: CGFloat(q.x)*s + vm.offset.width,
                //                 y: CGFloat(q.y)*s + vm.offset.height)
                //     }
                //     path.move(to: toPt(first))
                //     for q in poly.dropFirst() { path.addLine(to: toPt(q)) }
                //     ctx.stroke(path, with: .color(.teal), lineWidth: max(1, s * 0.15))
                // }
            }
            .background(Color(UIColor.secondarySystemBackground))
            // Pan + zoom
            .gesture(
                DragGesture().onChanged { vm.offset = $0.translation }
            )
            .simultaneousGesture(
                MagnificationGesture().onChanged { vm.zoom = max(0.3, min(5, $0)) }
            )
            // Tap-to-add-beacon with location
            .background(
                Color.clear
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onEnded { value in
                                // Treat taps (tiny drags) as beacon placement.
                                let pt = value.location
                                let world = vm.toWorld(pt, size: geo.size)
                                vm.addBeacon(at: world)
                            }
                    )
            )
            .onAppear { vm.recomputeContours() }
            .navigationBarItems(trailing: Button("Save") { onSave(vm.map) })
        }
        .navigationTitle("Map Editor")
    }
}
