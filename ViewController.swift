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
    var inputStream: InputStream?
    var isReading = false

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        imageView.frame = view.bounds
        imageView.contentMode = .scaleAspectFit
        imageView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(imageView)
        initSocket()
    }

    func initSocket() {
        var readStream: Unmanaged<CFReadStream>?
        CFStreamCreatePairWithSocketToHost(kCFAllocatorDefault, "127.0.0.1" as CFString, 5900, &readStream, nil)
        inputStream = readStream?.takeRetainedValue()
        inputStream?.delegate = self
        inputStream?.schedule(in: .main, forMode: .common)
        inputStream?.open()
        readLoop()
    }

    func readLoop() {
        DispatchQueue.global(qos: .userInteractive).async { [weak self] in
            while true {
                guard let self = self, let stream = self.inputStream, stream.streamStatus == .open else {
                    Thread.sleep(forTimeInterval: 1.0)
                    continue
                }

                var sizeBuffer = [UInt8](repeating: 0, count: 4)
                let bytesRead = stream.read(&sizeBuffer, maxLength: 4)
                guard bytesRead == 4 else {
                    Thread.sleep(forTimeInterval: 0.5)
                    continue
                }

                let totalSize = Int(UInt32(bigEndian: sizeBuffer.withUnsafeBytes { $0.load(as: UInt32.self) }))
                guard totalSize > 0 && totalSize < 10_000_000 else { continue }

                var imgData = Data()
                var remaining = totalSize
                let chunk = 16384
                var buffer = [UInt8](repeating: 0, count: chunk)

                while remaining > 0 {
                    let toRead = min(remaining, chunk)
                    let read = stream.read(&buffer, maxLength: toRead)
                    if read <= 0 { break }
                    imgData.append(buffer, count: read)
                    remaining -= read
                }

                if imgData.count == totalSize, let image = UIImage(data: imgData) {
                    DispatchQueue.main.async {
                        self.imageView.image = image
                    }
                }
            }
        }
    }
}
