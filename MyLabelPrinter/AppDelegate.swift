import Cocoa
import AppKit
@main
class AppDelegate: NSObject, NSApplicationDelegate {


func applicationDidFinishLaunching(_ aNotification: Notification) {
  AppMenu.install()
  NotificationCenter.default.post(name: Notification.Name("updateView"), object: nil, userInfo: nil)
}
  @MainActor
  static func quit() {
      NSApplication.shared.terminate(nil)
  }

func applicationWillTerminate(_ aNotification: Notification) {

}

func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    return true
}
func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
    return .terminateNow
}
func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    return true
}

}
