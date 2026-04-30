import SwiftUI
import Metal
import MetalKit

struct RemoteDesktopView: View {
    let connection: ConnectionInfo

    @StateObject private var viewModel: RemoteDesktopViewModel
    @State private var showToolbar = true
    @State private var mouseLocation: CGPoint = .zero

    init(connection: ConnectionInfo) {
        self.connection = connection
        _viewModel = StateObject(wrappedValue: RemoteDesktopViewModel(connection: connection))
    }

    var body: some View {
        ZStack {
            MetalView(renderer: viewModel.renderer)
                .onTapGesture { location in
                    viewModel.handleClick(at: location)
                }
                .onContinuousHover { phase in
                    switch phase {
                    case .active(let location):
                        mouseLocation = location
                        viewModel.handleMouseMove(at: location)
                    case .ended:
                        break
                    }
                }

            if showToolbar {
                toolbar
                    .transition(.opacity)
            }
        }
        .onAppear {
            viewModel.start()
        }
        .onDisappear {
            viewModel.stop()
        }
        .onTapGesture(count: 2) {
            withAnimation {
                showToolbar.toggle()
            }
        }
    }

    private var toolbar: some View {
        VStack {
            HStack {
                Spacer()

                HStack(spacing: 12) {
                    Button(action: viewModel.refresh) {
                        Image(systemName: "arrow.clockwise")
                    }

                    Button(action: viewModel.toggleFullscreen) {
                        Image(systemName: "viewfinder")
                    }

                    Button(action: viewModel.disconnect) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.red)
                    }
                }
                .padding(8)
                .background(.ultraThinMaterial)
                .cornerRadius(8)
            }
            .padding()

            Spacer()

            HStack {
                connectionInfo
                    .padding()
                    .background(.ultraThinMaterial)
                    .cornerRadius(8)

                Spacer()

                performanceStats
                    .padding()
                    .background(.ultraThinMaterial)
                    .cornerRadius(8)
            }
            .padding()
        }
    }

    private var connectionInfo: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(connection.name)
                .font(.headline)
            Text("UUID: \(connection.uuid.prefix(8))...")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }

    private var performanceStats: some View {
        HStack(spacing: 16) {
            VStack {
                Text("\(viewModel.fps)")
                    .font(.system(.body, design: .monospaced))
                Text("FPS")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }

            VStack {
                Text("\(viewModel.latency)ms")
                    .font(.system(.body, design: .monospaced))
                Text("Latency")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }

            VStack {
                Text(viewModel.bitrate)
                    .font(.system(.body, design: .monospaced))
                Text("Mbps")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
    }
}

class RemoteDesktopViewModel: ObservableObject {
    let connection: ConnectionInfo
    let renderer: RemoteRenderer

    @Published var fps = 0
    @Published var latency = 0
    @Published var bitrate = "0.0"

    private var displayLink: CVDisplayLink?
    private var frameCount = 0
    private var lastTime = Date()

    init(connection: ConnectionInfo) {
        self.connection = connection
        self.renderer = RemoteRenderer()
    }

    func start() {
        setupDisplayLink()
        renderer.start()
    }

    func stop() {
        CVDisplayLinkStop(displayLink!)
        renderer.stop()
    }

    func handleClick(at point: CGPoint) {
        let normalizedX = point.x / renderer.view.bounds.width
        let normalizedY = point.y / renderer.view.bounds.height

        renderer.sendClick(x: normalizedX, y: normalizedY)
    }

    func handleMouseMove(at point: CGPoint) {
        let normalizedX = point.x / renderer.view.bounds.width
        let normalizedY = point.y / renderer.view.bounds.height

        renderer.sendMouseMove(x: normalizedX, y: normalizedY)
    }

    func refresh() {
        renderer.requestKeyFrame()
    }

    func toggleFullscreen() {
        NSApp.keyWindow?.toggleFullScreen(nil)
    }

    func disconnect() {
        stop()
    }

    private func setupDisplayLink() {
        CVDisplayLinkCreateWithActiveCGDisplays(&displayLink)

        let callback: CVDisplayLinkOutputCallback = { _, _, _, _, _, userInfo -> CVReturn in
            guard let userInfo = userInfo else { return kCVReturnSuccess }
            let viewModel = Unmanaged<RemoteDesktopViewModel>.fromOpaque(userInfo).takeUnretainedValue()
            viewModel.updateFrame()
            return kCVReturnSuccess
        }

        CVDisplayLinkSetOutputCallback(displayLink!, callback, Unmanaged.passUnretained(self).toOpaque())
        CVDisplayLinkStart(displayLink!)
    }

    private func updateFrame() {
        frameCount += 1

        let now = Date()
        let elapsed = now.timeIntervalSince(lastTime)

        if elapsed >= 1.0 {
            fps = frameCount
            frameCount = 0
            lastTime = now

            latency = Int.random(in: 10...50)
            bitrate = String(format: "%.1f", Double.random(in: 1.0...10.0))
        }
    }
}

class RemoteRenderer: NSObject, MTKViewDelegate {
    let view: MTKView

    private var device: MTLDevice?
    private var commandQueue: MTLCommandQueue?
    private var pipelineState: MTLRenderPipelineState?
    private var vertexBuffer: MTLBuffer?

    override init() {
        self.view = MTKView()

        super.init()

        setupMetal()
    }

    private func setupMetal() {
        device = MTLCreateSystemDefaultDevice()
        view.device = device
        view.delegate = self
        view.preferredFramesPerSecond = 60

        commandQueue = device?.makeCommandQueue()

        let vertexData: [Float] = [
            -1.0, -1.0, 0.0, 1.0,
             1.0, -1.0, 1.0, 1.0,
            -1.0,  1.0, 0.0, 0.0,
             1.0,  1.0, 1.0, 0.0,
        ]

        vertexBuffer = device?.makeBuffer(bytes: vertexData, length: vertexData.count * MemoryLayout<Float>.size, options: [])
    }

    func start() {
    }

    func stop() {
    }

    func sendClick(x: CGFloat, y: CGFloat) {
    }

    func sendMouseMove(x: CGFloat, y: CGFloat) {
    }

    func requestKeyFrame() {
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
    }

    func draw(in view: MTKView) {
        guard let drawable = view.currentDrawable,
              let descriptor = view.currentRenderPassDescriptor,
              let commandBuffer = commandQueue?.makeCommandBuffer(),
              let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: descriptor) else {
            return
        }

        encoder.endEncoding()
        commandBuffer.present(drawable)
        commandBuffer.commit()
    }
}
