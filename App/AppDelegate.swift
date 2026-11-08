import UIKit
import GossipCore

@main
final class AppDelegate: UIResponder, UIApplicationDelegate {
  var window: UIWindow?
  func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
    do { try GameData.load(Art.url("data.json")) } catch { fatalError("GameData/data.json: \(error)") }
    let w = UIWindow(frame: UIScreen.main.bounds)
    w.rootViewController = GameVC()
    w.makeKeyAndVisible()
    window = w
    return true
  }
  func application(_ application: UIApplication, supportedInterfaceOrientationsFor window: UIWindow?) -> UIInterfaceOrientationMask { .portrait }
}
