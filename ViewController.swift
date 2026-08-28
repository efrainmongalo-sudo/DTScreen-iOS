import UIKit

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

class ScreenViewController: UIViewController, StreamDelegate {
    let imageView = UIImageView()
    let statusLabel = UILabel()
    var inputStream: InputStream?
    var isRunning = false

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black

        imageView.frame = view.bounds
        imageView.contentMode = .scaleAspectFit
        imageView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(imageView)

        statusLabel.frame = CGRect(x: 20, y: 20, width: 300, height: 40)
        statusLabel.textColor = UIColor(red: 0.0, green: 0.8, blue: 1.0, alpha: 1.0)
        statusLabel.font = UIFont.boldSystemFont(ofSize: 16)
        statusLabel.text = "DT Screen: Conectando USB..."
        view.addSubview(statusLabel)

        startStreamingLoop()
    }

    func startStreamingLoop() {
        isRunning = true
        DispatchQueue.global(qos: .userInteractive).async { [weak self] in
            while self?.isRunning == true {
                self?.connectAndRead()
                Thread.sleep(forTimeInterval: 1.0)
            }
        }
    }

    func connectAndRead() {
        var readStream: Unmanaged<CFReadStream>?
        CFStreamCreatePairWithSocketToHost(kCFAllocatorDefault, "127.0.0.1" as CFString, 5900, &readStream, nil)
        guard let stream = readStream?.takeRetainedValue() else { return }
        
        stream.open()
        defer {
            stream.close()
        }

        DispatchQueue.main.async {
            self.statusLabel.text = "DT Screen: Transmitiendo 60 FPS"
            UIView.animate(withDuration: 1.0, delay: 2.0, options: [], animations: {
                self.statusLabel.alpha = 0
            }, completion: nil)
        }

        while stream.streamStatus == .open {
            var sizeBuf = [UInt8](repeating: 0, count: 4)
            var bytesRead = 0
            while bytesRead < 4 {
                let n = stream.read(&sizeBuf[bytesRead], maxLength: 4 - bytesRead)
                if n <= 0 { return }
                bytesRead += n
            }

            let totalSize = Int(UInt32(bigEndian: sizeBuf.withUnsafeBytes { $0.load(as: UInt32.self) }))
            guard totalSize > 0 && totalSize < 15_000_000 else { return }

            var data = Data(count: totalSize)
            var totalRead = 0
            let success = data.withUnsafeMutableBytes { (ptr: UnsafeMutableRawBufferPointer) -> Bool in
                guard let base = ptr.baseAddress?.assumingMemoryBound(to: UInt8.self) else { return false }
                while totalRead < totalSize {
                    let n = stream.read(base + totalRead, maxLength: totalSize - totalRead)
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
