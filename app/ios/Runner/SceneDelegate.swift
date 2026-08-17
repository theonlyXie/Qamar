import Flutter
import UIKit

class SceneDelegate: FlutterSceneDelegate {
  override func scene(_ scene: UIScene, openURLContexts URLContexts: Set<UIOpenURLContext>) {
    for ctx in URLContexts {
      QamarQuickBridge.enqueue(url: ctx.url)
    }
    super.scene(scene, openURLContexts: URLContexts)
  }
}
