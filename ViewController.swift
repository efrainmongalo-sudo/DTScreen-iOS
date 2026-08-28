import UIKit
import Network

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
    var connection: NWConnection?

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        imageView.frame = view.bounds
        imageView.contentMode = .scaleAspectFit
        imageView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(imageView)
        connectToHost()
    }

    func connectToHost() {
        let endpoint = NWEndpoint.hostPort(host: "127.0.0.1", port: 5900)
        connection = NWConnection(to: endpoint, using: .tcp)
        connection?.stateUpdateHandler = { [weak self] state in
            if case .ready = state {
                self?.receiveFrame()
            }
        }
        connection?.start(queue: .main)
    }

    func receiveFrame() {
        connection?.receive(minimumIncompleteLength: 4, maximumLength: 4) { [weak self] data, _, _, error in
            guard let data = data, data.count == 4, error == nil else {
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) { self?.connectToHost() }
                return
            }
            let size = data.withUnsafeBytes { $0.load(as: UInt32.self).bigEndian }
            self?.connection?.receive(minimumIncompleteLength: Int(size), maximumLength: Int(size)) { imgData, _, _, _ in
                if let imgData = imgData, let img = UIImage(data: imgData) {
                    self?.imageView.image = img
                }
                self?.receiveFrame()
            }
        }
    }
}
