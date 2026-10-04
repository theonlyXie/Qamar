import Flutter
import UIKit

class SceneDelegate: FlutterSceneDelegate {
  override func scene(_ scene: UIScene, openURLContexts URLContexts: Set<UIOpenURLContext>) {
    for ctx in URLContexts {
      QamarQuickBridge.enqueue(url: ctx.url)
    }
    super.scene(scene, openURLContexts: URLContexts)
  }

  // Universal links (https://dr-qamar.com/i/<code>) arrive as a browsing
  // activity. Needs the Associated Domains capability (Runner.entitlements,
  // applinks:dr-qamar.com) and the site's apple-app-site-association.
  override func scene(_ scene: UIScene, continue userActivity: NSUserActivity) {
    if userActivity.activityType == NSUserActivityTypeBrowsingWeb, let url = userActivity.webpageURL {
      QamarQuickBridge.enqueue(url: url)
    }
    super.scene(scene, continue: userActivity)
  }
}
