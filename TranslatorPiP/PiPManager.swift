import AVKit
import UIKit

final class PiPManager: NSObject {
    private var pipController: AVPictureInPictureController?
    private var contentSource: AVPictureInPictureController.ContentSource?
    private(set) var overlayViewController: PiPOverlayViewController?
    private(set) var isPiPActive = false

    var onPiPActiveChange: ((Bool) -> Void)?

    func setup(preferredContentSize: CGSize = CGSize(width: 320, height: 160)) {
        guard AVPictureInPictureController.isPictureInPictureSupported() else { return }

        let overlayVC = PiPOverlayViewController()
        overlayVC.preferredContentSize = preferredContentSize
        self.overlayViewController = overlayVC

        contentSource = AVPictureInPictureController.ContentSource(
            activeVideoCallSourceView: UIView(),
            contentViewController: overlayVC
        )

        guard let contentSource else { return }
        pipController = AVPictureInPictureController(contentSource: contentSource)
        pipController?.delegate = self
        pipController?.canStartPictureInPictureAutomaticallyFromInline = true
    }

    func startPiP() {
        guard let pip = pipController, pip.isPictureInPictureActive == false else { return }
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
}
