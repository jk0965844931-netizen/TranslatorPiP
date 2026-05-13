import AVKit
import UIKit

final class PiPManager: NSObject {
    private var pipController: AVPictureInPictureController?
    private(set) var overlayViewController: PiPOverlayViewController?
    private(set) var isPiPActive = false

    var onPiPActiveChange: ((Bool) -> Void)?

    /// Must be called from viewDidAppear so sourceView is in the live window hierarchy.
    func setup(sourceView: UIView) {
        guard AVPictureInPictureController.isPictureInPictureSupported() else {
            print("PiP: not supported on this device")
            return
        }

        let overlayVC = PiPOverlayViewController()
        overlayVC.preferredContentSize = CGSize(width: 300, height: 150)
        self.overlayViewController = overlayVC

        let contentSource = AVPictureInPictureController.ContentSource(
            activeVideoCallSourceView: sourceView,          // must be in a real window
            contentViewController: overlayVC
        )

        let pip = AVPictureInPictureController(contentSource: contentSource)
        pip.delegate = self
        pip.canStartPictureInPictureAutomaticallyFromInline = true
        self.pipController = pip
    }

    func startPiP() {
        guard let pip = pipController else {
            print("PiP: controller not ready — call setup(sourceView:) first from viewDidAppear")
            return
        }
        guard !pip.isPictureInPictureActive else { return }
        pip.startPictureInPicture()
    }

    func stopPiP() {
        guard let pip = pipController, pip.isPictureInPictureActive else { return }
        pip.stopPictureInPicture()
    }

    func update(original: String, translated: String) {
        overlayViewController?.update(original: original, translated: translated)
    }

    func updateLanguage(from: String, to: String) {
        overlayViewController?.updateLanguageBadge(from: from, to: to)
    }

    func setListening(_ active: Bool) {
        overlayViewController?.setListening(active)
    }
}

extension PiPManager: AVPictureInPictureControllerDelegate {
    func pictureInPictureControllerDidStartPictureInPicture(_ controller: AVPictureInPictureController) {
        isPiPActive = true
        onPiPActiveChange?(true)
    }

    func pictureInPictureControllerDidStopPictureInPicture(_ controller: AVPictureInPictureController) {
        isPiPActive = false
        onPiPActiveChange?(false)
    }

    func pictureInPictureController(
        _ controller: AVPictureInPictureController,
        failedToStartPictureInPictureWithError error: Error
    ) {
        print("PiP failed: \(error.localizedDescription)")
    }

    func pictureInPictureControllerWillStartPictureInPicture(_ controller: AVPictureInPictureController) {
        print("PiP: will start")
    }
}
