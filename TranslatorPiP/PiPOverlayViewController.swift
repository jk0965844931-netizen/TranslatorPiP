import UIKit
import AVKit

final class PiPOverlayViewController: AVPictureInPictureVideoCallViewController {
    private let containerView = UIView()
    private let originalLabel = UILabel()
    private let translatedLabel = UILabel()
    private let languageBadge = UILabel()
    private let divider = UIView()
    private let waveformView = WaveformIndicatorView()

    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
    }

    private func setupUI() {
        view.backgroundColor = UIColor.black.withAlphaComponent(0.85)
        view.layer.cornerRadius = 12
        view.clipsToBounds = true

        let gradient = CAGradientLayer()
        gradient.colors = [
            UIColor(red: 0.07, green: 0.07, blue: 0.12, alpha: 0.95).cgColor,
            UIColor(red: 0.05, green: 0.05, blue: 0.10, alpha: 0.95).cgColor
        ]
        gradient.frame = view.bounds
        view.layer.insertSublayer(gradient, at: 0)

        containerView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(containerView)

        languageBadge.font = .systemFont(ofSize: 9, weight: .semibold)
        languageBadge.textColor = UIColor(red: 0.4, green: 0.8, blue: 1.0, alpha: 1)
        languageBadge.textAlignment = .center
        languageBadge.text = "LIVE TRANSLATION"
        languageBadge.translatesAutoresizingMaskIntoConstraints = false

        originalLabel.font = .systemFont(ofSize: 13, weight: .regular)
        originalLabel.textColor = UIColor.white.withAlphaComponent(0.6)
        originalLabel.numberOfLines = 2
        originalLabel.textAlignment = .center
        originalLabel.text = "กำลังฟัง..."
        originalLabel.translatesAutoresizingMaskIntoConstraints = false

        divider.backgroundColor = UIColor.white.withAlphaComponent(0.15)
        divider.translatesAutoresizingMaskIntoConstraints = false

        translatedLabel.font = .systemFont(ofSize: 16, weight: .semibold)
        translatedLabel.textColor = .white
        translatedLabel.numberOfLines = 3
        translatedLabel.textAlignment = .center
        translatedLabel.text = "—"
        translatedLabel.translatesAutoresizingMaskIntoConstraints = false

        waveformView.translatesAutoresizingMaskIntoConstraints = false

        containerView.addSubview(languageBadge)
        containerView.addSubview(waveformView)
        containerView.addSubview(originalLabel)
        containerView.addSubview(divider)
        containerView.addSubview(translatedLabel)

        NSLayoutConstraint.activate([
            containerView.topAnchor.constraint(equalTo: view.topAnchor, constant: 8),
            containerView.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -8),
            containerView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 8),
            containerView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -8),

            languageBadge.topAnchor.constraint(equalTo: containerView.topAnchor),
            languageBadge.centerXAnchor.constraint(equalTo: containerView.centerXAnchor),

            waveformView.topAnchor.constraint(equalTo: languageBadge.bottomAnchor, constant: 4),
            waveformView.centerXAnchor.constraint(equalTo: containerView.centerXAnchor),
            waveformView.heightAnchor.constraint(equalToConstant: 16),
            waveformView.widthAnchor.constraint(equalToConstant: 60),

            originalLabel.topAnchor.constraint(equalTo: waveformView.bottomAnchor, constant: 4),
            originalLabel.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            originalLabel.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),

            divider.topAnchor.constraint(equalTo: originalLabel.bottomAnchor, constant: 6),
            divider.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: 16),
            divider.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -16),
            divider.heightAnchor.constraint(equalToConstant: 0.5),

            translatedLabel.topAnchor.constraint(equalTo: divider.bottomAnchor, constant: 6),
            translatedLabel.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            translatedLabel.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
            translatedLabel.bottomAnchor.constraint(lessThanOrEqualTo: containerView.bottomAnchor)
        ])
    }

    func update(original: String, translated: String) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            UIView.transition(with: self.originalLabel, duration: 0.2, options: .transitionCrossDissolve) {
                self.originalLabel.text = original.isEmpty ? "กำลังฟัง..." : original
            }
            UIView.transition(with: self.translatedLabel, duration: 0.25, options: .transitionCrossDissolve) {
                self.translatedLabel.text = translated.isEmpty ? "—" : translated
            }
        }
    }

    func updateLanguageBadge(from: String, to: String) {
        DispatchQueue.main.async { [weak self] in
            self?.languageBadge.text = "\(from.uppercased()) → \(to.uppercased())"
        }
    }

    func setListening(_ active: Bool) {
        DispatchQueue.main.async { [weak self] in
            if active {
                self?.waveformView.startAnimating()
            } else {
                self?.waveformView.stopAnimating()
            }
        }
    }
}

final class WaveformIndicatorView: UIView {
    private var bars: [UIView] = []
    private var animators: [UIViewPropertyAnimator] = []
    private let barCount = 5

    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    private func setup() {
        for _ in 0..<barCount {
            let bar = UIView()
            bar.backgroundColor = UIColor(red: 0.4, green: 0.8, blue: 1.0, alpha: 0.8)
            bar.layer.cornerRadius = 2
            addSubview(bar)
            bars.append(bar)
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let totalSpacing = CGFloat(barCount - 1) * 3
        let barWidth: CGFloat = (bounds.width - totalSpacing) / CGFloat(barCount)
        for (i, bar) in bars.enumerated() {
            let x = CGFloat(i) * (barWidth + 3)
            bar.frame = CGRect(x: x, y: bounds.midY - 4, width: barWidth, height: 8)
        }
    }

    func startAnimating() {
        stopAnimating()
        for (i, bar) in bars.enumerated() {
            let delay = Double(i) * 0.1
            let animator = UIViewPropertyAnimator(duration: 0.4, curve: .easeInOut) {
                bar.transform = CGAffineTransform(scaleX: 1, y: 2.5)
            }
            animator.addCompletion { [weak self] _ in
                guard let self else { return }
                self.reverseBar(bar, index: i)
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                animator.startAnimation()
            }
            animators.append(animator)
        }
    }

    private func reverseBar(_ bar: UIView, index: Int) {
        let animator = UIViewPropertyAnimator(duration: 0.4, curve: .easeInOut) {
            bar.transform = .identity
        }
        animator.addCompletion { [weak self] _ in
            guard let self else { return }
            if !self.animators.isEmpty {
                self.animateBar(bar, index: index)
            }
        }
        animator.startAnimation()
    }

    private func animateBar(_ bar: UIView, index: Int) {
        let height = CGFloat.random(in: 1.2...3.0)
        let animator = UIViewPropertyAnimator(duration: Double.random(in: 0.25...0.5), curve: .easeInOut) {
            bar.transform = CGAffineTransform(scaleX: 1, y: height)
        }
        animator.addCompletion { [weak self] _ in
            guard let self, !self.animators.isEmpty else { return }
            self.reverseBar(bar, index: index)
        }
        animator.startAnimation()
        animators.append(animator)
    }

    func stopAnimating() {
        animators.forEach { $0.stopAnimation(true) }
        animators.removeAll()
        bars.forEach { $0.transform = .identity }
    }
}
