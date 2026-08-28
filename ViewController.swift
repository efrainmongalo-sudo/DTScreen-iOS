import UIKit
import Foundation
import Darwin

@main
class AppDelegate: UIResponder, UIApplicationDelegate {
    var window: UIWindow?

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        UIApplication.shared.isStatusBarHidden = true
        UIApplication.shared.isIdleTimerDisabled = true
        
        let screenBounds = UIScreen.main.bounds
        let win = UIWindow(frame: screenBounds)
        win.rootViewController = ScreenViewController()
        win.makeKeyAndVisible()
        self.window = win
        return true
    }
}

class ScreenViewController: UIViewController {
    let screenLayer = CALayer()
    var serverFd: Int32 = -1
    var isRunning = true

    override var prefersStatusBarHidden: Bool { return true }
    override var prefersHomeIndicatorAutoHidden: Bool { return true }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black

        screenLayer.frame = view.bounds
        screenLayer.contentsGravity = .resize
        screenLayer.actions = ["contents": NSNull()] // Desactivar animaciones para latencia cero
        view.layer.addSublayer(screenLayer)

        startServer()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        screenLayer.frame = view.bounds
        CATransaction.commit()
    }

    override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
        super.viewWillTransition(to: size, with: coordinator)
        coordinator.animate(alongsideTransition: { _ in
            self.screenLayer.frame = CGRect(origin: .zero, size: size)
        }, completion: nil)
    }

    func startServer() {
        DispatchQueue.global(qos: .userInteractive).async { [weak self] in
            guard let self = self else { return }
            self.serverFd = socket(AF_INET, SOCK_STREAM, 0)
            var opt: Int32 = 1
            setsockopt(self.serverFd, SOL_SOCKET, SO_REUSEADDR, &opt, socklen_t(MemoryLayout<Int32>.size))

            var addr = sockaddr_in()
            addr.sin_family = sa_family_t(AF_INET)
            addr.sin_port = in_port_t(5900).bigEndian
            addr.sin_addr.s_addr = in_addr_t(0)

            withUnsafePointer(to: &addr) {
                $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    _ = bind(self.serverFd, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
                }
            }

            listen(self.serverFd, 5)

            while self.isRunning {
                var clientAddr = sockaddr_in()
                var clientLen = socklen_t(MemoryLayout<sockaddr_in>.size)
                let clientFd = withUnsafeMutablePointer(to: &clientAddr) {
                    $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                        accept(self.serverFd, $0, &clientLen)
                    }
                }

                if clientFd < 0 { continue }
                
                // Configurar TCP_NODELAY para latencia ultra baja
                var noDelay: Int32 = 1
                setsockopt(clientFd, IPPROTO_TCP, TCP_NODELAY, &noDelay, socklen_t(MemoryLayout<Int32>.size))

                self.readClientData(clientFd: clientFd)
                close(clientFd)
            }
        }
    }

    func readClientData(clientFd: Int32) {
        var sizeBuf = [UInt8](repeating: 0, count: 4)
        while isRunning {
            var readCount = 0
            while readCount < 4 {
                let n = recv(clientFd, &sizeBuf[readCount], 4 - readCount, 0)
                if n <= 0 { return }
                readCount += n
            }

            let totalSize = Int(UInt32(bigEndian: sizeBuf.withUnsafeBytes { $0.load(as: UInt32.self) }))
            guard totalSize > 0 && totalSize < 15_000_000 else { return }

            var data = Data(count: totalSize)
            var totalRead = 0
            let success = data.withUnsafeMutableBytes { (ptr: UnsafeMutableRawBufferPointer) -> Bool in
                guard let base = ptr.baseAddress?.assumingMemoryBound(to: UInt8.self) else { return false }
                while totalRead < totalSize {
                    let n = recv(clientFd, base + totalRead, totalSize - totalRead, 0)
                    if n <= 0 { return false }
                    totalRead += n
                }
                return true
            }

            if !success { return }

            if let provider = CGDataProvider(data: data as CFData),
               let image = CGImage(jpegDataProviderSource: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent) {
                DispatchQueue.main.async {
                    self.screenLayer.contents = image
                }
            }
        }
    }
}
