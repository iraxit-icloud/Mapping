import Foundation
import ARKit
import simd
import Combine

@MainActor
final class ScanViewModel: NSObject, ObservableObject, ARSessionDelegate {
    @Published var status: String = "Initializing…"
    @Published var currentMap: Map2D
    @Published var floorY: Float?
    @Published var readyToSave = false

    // === State Machine additions ===
    @Published var scanState: ScanState = .idle
    @Published var metrics = ScanQualityMetrics()
    private var scanStartDate: Date?

    // Coaching voice timer
    private var coachingTimer: Timer?

    // Crosshair / placement (unchanged if you already have it)
    enum PlacementMode: Equatable { case none, beacon, doorwayStart, doorwayEnd(start: SIMD2<Float>) }
    @Published var placementMode: PlacementMode = .none

    enum CrosshairState: Equatable { case none, floorHit(SIMD2<Float>), wallHit(SIMD2<Float>) }
    @Published var crosshair: CrosshairState = .none

    let session = ARSession()

    // Map span and resolution
    private let metersWidth: Float = 20
    private let metersHeight: Float = 20
    private let resolution: Float = 0.05 // 5 cm

    // Run guard
    private var isRunning = false

    // --- Floor lock stabilizer ---
    private var floorSamples: [Float] = []   // recent downward raycast y's
    private let maxFloorSamples = 25
    private let floorVarianceThreshold: Float = 0.0009 // (0.03 m)^2 = 3cm std^2

    override init() {
        let spec = GridSpec(resolution: 0.05,
                            width: Int(20 / 0.05),
                            height: Int(20 / 0.05),
                            originWorldXZ: .zero)
        self.currentMap = Map2D(title: "New Map", spec: spec)
        super.init()
        session.delegate = self
    }

    // MARK: - Session start/stop

    func start() {
        guard !isRunning else {
            status = "Already scanning."
            return
        }
        isRunning = true
        floorY = nil
        floorSamples.removeAll()

        let cfg = ARWorldTrackingConfiguration()
        cfg.sceneReconstruction = .mesh
        cfg.planeDetection = [.horizontal, .vertical]
        cfg.environmentTexturing = .automatic
        session.run(cfg, options: [.resetTracking, .removeExistingAnchors])
        status = "Move slowly… initialize tracking."
    }

    func stop() {
        guard isRunning else {
            status = "Not running."
            return
        }
        session.pause()
        isRunning = false
        stopCoachingTimer()
        status = "Stopped."
    }

    // === New flow methods for HUD ===

    func startScanningFlow() {
        VoiceFeedback.shared.say("Ready to scan. Move slowly and look at floors and walls.")
        scanState = .scanning
        scanStartDate = Date()
        startCoachingTimer()
        start()
    }

    func finishAndSave() {
        guard scanState == .scanning else { return }
        scanState = .finalizing
        VoiceFeedback.shared.say("Finalizing the map. Hold steady.")
        stop()
        saveAll()
        scanState = .saved(mapId: currentMap.id)
        VoiceFeedback.shared.say("Map saved successfully.")
    }

    // MARK: - Tap & Crosshair (if you use these)

    func beginBeaconPlacement() { placementMode = .beacon; status = "Aim at FLOOR (green) and tap." }
    func beginDoorwayPlacement() { placementMode = .doorwayStart; status = "Aim at WALL (blue) and tap first side." }
    func cancelPlacement() { placementMode = .none; status = "Placement cancelled." }

    func handleTap(at screenPoint: CGPoint, viewSize: CGSize, in view: ARSCNView) {
        switch placementMode {
        case .none: return
        case .beacon:
            if let p = raycastWorldXZ(at: screenPoint, in: view, alignment: .horizontal) {
                addBeacon(at: p, name: "Beacon \(currentMap.beacons.count+1)")
                placementMode = .none
                status = "Beacon added."
            } else { status = "No floor hit. Try again." }

        case .doorwayStart:
            if let p = raycastWorldXZ(at: screenPoint, in: view, alignment: .vertical) {
                placementMode = .doorwayEnd(start: p)
                status = "Aim at opposite side and tap."
            } else { status = "No wall hit. Try again." }

        case .doorwayEnd(let start):
            if let p = raycastWorldXZ(at: screenPoint, in: view, alignment: .vertical) {
                addDoorway(a: start, b: p, width: 0.9)
                placementMode = .none
                status = "Doorway added."
            } else { status = "No wall hit. Try again." }
        }
    }

    func updateCrosshair(at screenPoint: CGPoint, in view: ARSCNView) {
        let preferVertical: Bool = {
            if case .doorwayStart = placementMode { return true }
            if case .doorwayEnd = placementMode { return true }
            return false
        }()
        if preferVertical, let p = raycastWorldXZ(at: screenPoint, in: view, alignment: .vertical) {
            crosshair = .wallHit(p); return
        }
        if let p = raycastWorldXZ(at: screenPoint, in: view, alignment: .horizontal) {
            crosshair = .floorHit(p); return
        }
        crosshair = .none
    }

    // MARK: - ARSessionDelegate (Swift 6 nonisolated + hop)

    nonisolated func session(_ session: ARSession, didUpdate frame: ARFrame) {
        // Update quality metrics (do not retain frame)
        Task { @MainActor in
            if let start = self.scanStartDate {
                self.metrics.secondsElapsed = Date().timeIntervalSince(start)
            }
            self.metrics.featurePointCount = frame.rawFeaturePoints?.points.count ?? 0
            self.metrics.worldMappingStatus = frame.worldMappingStatus
        }

        Task { @MainActor in
            // Show tracking state in status until floor locks
            if self.floorY == nil {
                switch frame.camera.trackingState {
                case .normal:
                    // Try to lock floor once tracking is good
                    self.tryLockFloor(from: frame)
                case .limited(let reason):
                    self.status = "Tracking limited: \(reason.localizedDescription). Move slowly."
                case .notAvailable:
                    self.status = "Tracking not available."
                }
            }
        }
    }

    // ARKit provides this delegate for state changes (keeps status responsive)
    nonisolated func session(_ session: ARSession, cameraDidChangeTrackingState camera: ARCamera) {
        Task { @MainActor in
            guard self.floorY == nil else { return }
            switch camera.trackingState {
            case .normal: self.status = "Tracking normal. Scanning…"
            case .limited(let reason): self.status = "Tracking limited: \(reason.localizedDescription)."
            case .notAvailable: self.status = "Tracking not available."
            }
        }
    }

    nonisolated func session(_ session: ARSession, didUpdate anchors: [ARAnchor]) {
        Task { @MainActor in
            guard self.isRunning else { return }
            var wrote = 0
            for anchor in anchors {
                guard let mesh = anchor as? ARMeshAnchor else { continue }
                self.project(mesh: mesh, wrote: &wrote)
            }
            if wrote > 0 {
                // (2) Recompute coverage metrics whenever grid changes
                self.recomputeCoverageMetrics()

                self.status = self.floorY == nil
                ? "Scanning… (floor pending)"
                : "Updated grid (\(wrote) cells). Keep scanning…"
            }
        }
    }

    // MARK: - Robust floor locking

    private func tryLockFloor(from frame: ARFrame) {
        // 1) Downward raycast from screen center to horizontal (estimated allowed)
        if let floorHitY = raycastDownY(from: frame) {
            pushFloorSample(floorHitY)
        }

        // 2) Fallbacks: planes labeled floor; else lowest horizontal plane
        if floorY == nil {
            let planes = frame.anchors
                .compactMap { $0 as? ARPlaneAnchor }
                .filter { $0.alignment == .horizontal }

            // Prefer explicitly-classified floor when available
            if #available(iOS 13.4, *) {
                if let floorPlane = planes.first(where: { $0.classification == .floor }) {
                    floorY = floorPlane.transform.columns.3.y
                }
            }

            // If still not set, pick the lowest horizontal plane we see
            if floorY == nil, let lowest = planes.min(by: {
                $0.transform.columns.3.y < $1.transform.columns.3.y
            }) {
                floorY = lowest.transform.columns.3.y
            }
        }

        // 3) Decide if we have stable samples
        if floorY == nil, floorSamples.count >= 10 {
            let (_, var_) = meanAndVariance(floorSamples)
            if var_ <= floorVarianceThreshold {
                // Stable enough — lock
                floorY = median(floorSamples)
                let cam = frame.camera.transform.columns.3
                currentMap.spec.originWorldXZ =
                    SIMD2<Float>(cam.x, cam.z) - SIMD2<Float>(metersWidth * 0.5, metersHeight * 0.5)
                status = "Floor locked at y=\(String(format: "%.02f", floorY!)) m"
            } else {
                status = "Measuring floor… (σ=\(String(format: "%.02f", sqrt(var_))) m)"
            }
        }
    }

    private func raycastDownY(from frame: ARFrame) -> Float? {
        // screen center
        let size = frame.camera.imageResolution
        let center = CGPoint(x: CGFloat(size.width)/2.0, y: CGFloat(size.height)/2.0)
        let q = frame.raycastQuery(from: center, allowing: .estimatedPlane, alignment: .horizontal)
        let results = session.raycast(q)
        guard let first = results.first else { return nil }
        return first.worldTransform.columns.3.y
    }

    private func pushFloorSample(_ y: Float) {
        floorSamples.append(y)
        if floorSamples.count > maxFloorSamples { floorSamples.removeFirst(floorSamples.count - maxFloorSamples) }
    }

    // MARK: - Mesh → Grid (vertex-based rasterization)

    private func project(mesh: ARMeshAnchor, wrote: inout Int) {
        let geom = mesh.geometry
        let vBuf = geom.vertices.buffer.contents()
        let nBuf = geom.normals.buffer.contents()
        let vStride = geom.vertices.stride
        let nStride = geom.normals.stride
        let transform = mesh.transform

        for i in 0..<geom.vertices.count {
            let pLocal = vBuf.advanced(by: i * vStride).assumingMemoryBound(to: SIMD3<Float>.self).pointee
            let nLocal = nBuf.advanced(by: i * nStride).assumingMemoryBound(to: SIMD3<Float>.self).pointee

            let wp4 = transform * SIMD4<Float>(pLocal.x, pLocal.y, pLocal.z, 1.0)
            let wp = SIMD3<Float>(wp4.x, wp4.y, wp4.z)

            // upper-left 3x3 for normal
            let m3 = simd_float3x3(
                SIMD3<Float>(transform.columns.0.x, transform.columns.0.y, transform.columns.0.z),
                SIMD3<Float>(transform.columns.1.x, transform.columns.1.y, transform.columns.1.z),
                SIMD3<Float>(transform.columns.2.x, transform.columns.2.y, transform.columns.2.z)
            )
            let nWorld = simd_normalize(m3 * nLocal)

            // vertical surfaces are walls
            if abs(nWorld.y) < 0.35 {
                let gx = Int((wp.x - currentMap.spec.originWorldXZ.x) / currentMap.spec.resolution)
                let gy = Int((wp.z - currentMap.spec.originWorldXZ.y) / currentMap.spec.resolution)
                if gx >= 0, gy >= 0, gx < currentMap.spec.width, gy < currentMap.spec.height {
                    if currentMap.grid[currentMap.idx(gx, gy)] != .wall {
                        currentMap.setCell(x: gx, y: gy, to: .wall)
                        wrote += 1
                    }
                }
            }
        }
    }

    // MARK: - Editing

    func addDoorway(a: SIMD2<Float>, b: SIMD2<Float>, width: Float = 0.9) {
        let d = Doorway(a: a, b: b, width: max(0.4, width))
        currentMap.doorways.append(d)
        carveCorridor(along: d)
    }

    func addBeacon(at p: SIMD2<Float>, name: String) {
        currentMap.beacons.append(Beacon(position: p, name: name))
    }

    func worldToCell(_ p: SIMD2<Float>) -> SIMD2<Int> {
        let gx = Int((p.x - currentMap.spec.originWorldXZ.x) / currentMap.spec.resolution)
        let gy = Int((p.y - currentMap.spec.originWorldXZ.y) / currentMap.spec.resolution)
        return SIMD2(gx, gy)
    }

    private func carveCorridor(along d: Doorway) {
        let a = worldToCell(d.a)
        let b = worldToCell(d.b)
        let thickness = max(1, Int(round(d.width / currentMap.spec.resolution)))

        let dx = abs(b.x - a.x), sx = a.x < b.x ? 1 : -1
        let dy = -abs(b.y - a.y), sy = a.y < b.y ? 1 : -1
        var err = dx + dy
        var x = a.x, y = a.y
        while true {
            for oy in -thickness...thickness {
                for ox in -thickness...thickness {
                    if ox*ox + oy*oy <= thickness*thickness {
                        currentMap.setCell(x: x+ox, y: y+oy, to: .free)
                    }
                }
            }
            if x == b.x && y == b.y { break }
            let e2 = 2*err
            if e2 >= dy { err += dy; x += sx }
            if e2 <= dx { err += dx; y += sy }
        }
    }

    // MARK: - Distance-to-wall

    func computeDistanceField() {
        let W = currentMap.spec.width, H = currentMap.spec.height
        var out = [Float](repeating: .nan, count: W*H)
        var q: [(Int, Int)] = []
        for y in 0..<H {
            for x in 0..<W {
                if currentMap.grid[currentMap.idx(x, y)] == .wall {
                    out[currentMap.idx(x, y)] = 0
                    q.append((x, y))
                }
            }
        }
        let dirs = [(-1,0),(1,0),(0,-1),(0,1)]
        while !q.isEmpty {
            let (cx, cy) = q.removeFirst()
            let cd = out[currentMap.idx(cx, cy)]
            for (dx, dy) in dirs {
                let nx = cx + dx, ny = cy + dy
                guard nx>=0, ny>=0, nx<W, ny<H else { continue }
                let i = currentMap.idx(nx, ny)
                if currentMap.grid[i] == .free {
                    let nd = cd + currentMap.spec.resolution
                    if !(nd >= out[i]) { // also handles NaN
                        out[i] = nd
                        q.append((nx, ny))
                    }
                }
            }
        }
        currentMap.distanceField = DistanceField(width: W, height: H, meters: out)
        status = "Distance field computed."
    }

    // MARK: - Persist + Snapshots

    func saveAll() {
        do {
            try MapStorage.save(currentMap) // handles NaN encoding
            if let png = MapSnapshot.png(from: currentMap) {
                try png.write(to: try MapStorage.pngURL(for: currentMap.id), options: .atomic)
            }
            if let svg = MapSnapshot.svg(from: currentMap) {
                try svg.write(to: try MapStorage.svgURL(for: currentMap.id), options: .atomic)
            }
            readyToSave = true
            status = "Saved JSON + PNG + SVG."
        } catch {
            status = "Save failed: \(error.localizedDescription)"
        }
    }

    // MARK: - Raycast helpers

    func raycastWorldXZ(at pt: CGPoint, in view: ARSCNView,
                        alignment: ARRaycastQuery.TargetAlignment) -> SIMD2<Float>? {
        guard let frame = view.session.currentFrame else { return nil }
        let q = frame.raycastQuery(from: pt, allowing: .estimatedPlane, alignment: alignment)
        let results = session.raycast(q)
        guard let first = results.first else { return nil }
        let m = first.worldTransform
        return SIMD2<Float>(m.columns.3.x, m.columns.3.z)
    }

    // MARK: - Metrics helpers (NEW)

    /// (2) Recompute coverage based on your Map2D grid.
    private func recomputeCoverageMetrics() {
        let total = currentMap.grid.count
        guard total > 0 else {
            metrics.gridTotalCells = 0
            metrics.gridFilledCells = 0
            return
        }
        var filled = 0
        for cell in currentMap.grid {
            switch cell {
            case .unknown:
                break
            default:
                filled += 1
            }
        }
        metrics.gridTotalCells  = total
        metrics.gridFilledCells = filled
    }

    // (4) Unified voice coaching every ~3s
    private func startCoachingTimer() {
        coachingTimer?.invalidate()
        coachingTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.speakCoachingTick()
        }
    }

    private func stopCoachingTimer() {
        coachingTimer?.invalidate()
        coachingTimer = nil
    }

    private func speakCoachingTick() {
        let t = metrics.trackingScore
        let c = metrics.coveragePercent
        let o = metrics.overallScore

        if !metrics.meetsSaveThreshold {
            if t < 60 {
                VoiceFeedback.shared.say("Tracking \(t) percent. Move slowly and look at textured floors and walls.")
            } else if c < 25 {
                VoiceFeedback.shared.say("Coverage \(c) percent. Scan more of the room for better coverage.")
            } else {
                VoiceFeedback.shared.say("Overall \(o) percent. Almost there.")
            }
        } else {
            VoiceFeedback.shared.say("Overall \(o) percent. You can finish and save now.")
        }
    }

    // MARK: - Tiny math helpers

    private func meanAndVariance(_ xs: [Float]) -> (Float, Float) {
        guard !xs.isEmpty else { return (0, 0) }
        let m = xs.reduce(0, +) / Float(xs.count)
        let v = xs.reduce(0) { $0 + ( ($1 - m)*($1 - m) ) } / Float(xs.count)
        return (m, v)
    }

    private func median(_ xs: [Float]) -> Float {
        guard !xs.isEmpty else { return 0 }
        let s = xs.sorted()
        let n = s.count
        if n % 2 == 1 { return s[n/2] }
        return 0.5 * (s[n/2 - 1] + s[n/2])
    }
}

// Convenience for tracking-state text
private extension ARCamera.TrackingState.Reason {
    var localizedDescription: String {
        switch self {
        case .excessiveMotion: return "excessive motion"
        case .insufficientFeatures: return "insufficient features"
        case .initializing: return "initializing"
        case .relocalizing: return "relocalizing"
        @unknown default: return "unknown"
        }
    }
}
