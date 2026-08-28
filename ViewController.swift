import UIKit
import Foundation
import Darwin

@main
class AppDelegate: UIResponder, UIApplicationDelegate {
    var window: UIWindow?

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        window = UIWindow(frame: UIScreen.main.bounds)
        window?.rootViewController = ScreenViewController()
        window?.makeKeyAndVisible()
        return true
    }
}

class ScreenViewController: UIViewController {
    let imageView = UIImageView()
    let statusLabel = UILabel()
    var serverFd: Int32 = -1
    var isRunning = true

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black

        imageView.frame = view.bounds
        imageView.contentMode = .scaleAspectFit
        imageView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(imageView)

        statusLabel.frame = CGRect(x: 20, y: 20, width: 400, height: 40)
        statusLabel.textColor = UIColor(red: 0.0, green: 0.85, blue: 1.0, alpha: 1.0)
        statusLabel.font = UIFont.boldSystemFont(ofSize: 18)
        statusLabel.text = "DT Screen: Esperando senal USB..."
        view.addSubview(statusLabel)

        startServer()
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
            addr.sin_addr.s_addr = in_addr_t(0) // INADDR_ANY

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

                DispatchQueue.main.async {
                    self.statusLabel.text = "DT Screen: Transmitiendo 60 FPS"
                    UIView.animate(withDuration: 1.0, delay: 1.5, options: [], animations: {
                        self.statusLabel.alpha = 0
                    }, completion: nil)
                }

                self.readClientData(clientFd: clientFd)
                close(clientFd)

                DispatchQueue.main.async {
                    self.statusLabel.alpha = 1.0
                    self.statusLabel.text = "DT Screen: Esperando senal USB..."
                }
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
            guard totalSize > 0 && totalSize < 20_000_000 else { return }

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

            if let img = UIImage(data: data) {
                DispatchQueue.main.async {
                    self.imageView.image = img
                }
            }
        }
    }
}
