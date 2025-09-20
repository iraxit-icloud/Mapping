import SwiftUI
import ARKit

struct ARViewContainer: UIViewRepresentable {
    @ObservedObject var vm: ScanViewModel

    func makeCoordinator() -> Coordinator { Coordinator(vm: vm) }

    func makeUIView(context: Context) -> ARSCNView {
        let v = ARSCNView(frame: .zero)
        v.session = vm.session
        v.automaticallyUpdatesLighting = true
        v.debugOptions = [.showWorldOrigin, .showFeaturePoints]

        // Tap to place
        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleTap(_:)))
        v.addGestureRecognizer(tap)

        // Start crosshair updater
        context.coordinator.attach(view: v)
        return v
    }

    func updateUIView(_ uiView: ARSCNView, context: Context) { }

    final class Coordinator: NSObject {
        private weak var view: ARSCNView?
        private weak var displayLink: CADisplayLink?
        private let vm: ScanViewModel

        init(vm: ScanViewModel) {
            self.vm = vm
            super.init()
        }

        func attach(view: ARSCNView) {
            self.view = view
            let link = CADisplayLink(target: self, selector: #selector(step))
            link.add(to: .main, forMode: .common)
            self.displayLink = link
        }

        deinit { displayLink?.invalidate() }

        @objc func step() {
            guard let v = view else { return }
            let size = v.bounds.size
            let center = CGPoint(x: size.width/2, y: size.height/2)
            Task { @MainActor in
                vm.updateCrosshair(at: center, in: v)
            }
        }

        @objc func handleTap(_ gr: UITapGestureRecognizer) {
            guard let v = view else { return }
            let pt = gr.location(in: v)
            Task { @MainActor in
                vm.handleTap(at: pt, viewSize: v.bounds.size, in: v)
            }
        }
    }
}
