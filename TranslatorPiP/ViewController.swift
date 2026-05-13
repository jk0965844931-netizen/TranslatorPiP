import UIKit
import AVKit

final class ViewController: UIViewController {
    private let orchestrator = TranslationOrchestrator()
    private let pipManager = PiPManager()

    private let titleLabel = UILabel()
    private let subtitleLabel = UILabel()
    private let statusCard = UIView()
    private let statusLabel = UILabel()
    private let originalTextView = UITextView()
    private let translatedTextView = UITextView()
    private let startStopButton = UIButton(type: .system)
    private let pipButton = UIButton(type: .system)
    private let langStackView = UIStackView()
    private let sourcePicker = UIButton(type: .system)
    private let targetPicker = UIButton(type: .system)
    private let swapButton = UIButton(type: .system)

    private var selectedSource: LanguageOption = .english
    private var selectedTarget: LanguageOption = .thai
    private var isRunning = false

    override func viewDidLoad() {
        super.viewDidLoad()
        setupGradientBackground()
        setupUI()
        setupOrchestrator()
        setupPiP()
    }

    private func setupGradientBackground() {
        let gradient = CAGradientLayer()
        gradient.colors = [
            UIColor(red: 0.06, green: 0.06, blue: 0.14, alpha: 1).cgColor,
            UIColor(red: 0.08, green: 0.08, blue: 0.20, alpha: 1).cgColor
        ]
        gradient.startPoint = CGPoint(x: 0, y: 0)
        gradient.endPoint = CGPoint(x: 1, y: 1)
        gradient.frame = view.bounds
        view.layer.insertSublayer(gradient, at: 0)
    }

    private func setupUI() {
        titleLabel.text = "TranslatorPiP"
        titleLabel.font = .systemFont(ofSize: 28, weight: .bold)
        titleLabel.textColor = .white
        titleLabel.textAlignment = .center
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        subtitleLabel.text = "แปลเสียงหน้าจอแบบ Real-time"
        subtitleLabel.font = .systemFont(ofSize: 14, weight: .regular)
        subtitleLabel.textColor = UIColor.white.withAlphaComponent(0.55)
        subtitleLabel.textAlignment = .center
        subtitleLabel.translatesAutoresizingMaskIntoConstraints = false

        setupLanguagePicker()
        setupStatusCard()
        setupTextViews()
        setupButtons()
        layoutAll()
    }

    private func setupLanguagePicker() {
        langStackView.axis = .horizontal
        langStackView.spacing = 8
        langStackView.alignment = .center
        langStackView.distribution = .fill
        langStackView.translatesAutoresizingMaskIntoConstraints = false

        configurePickerButton(sourcePicker, title: selectedSource.rawValue)
        configurePickerButton(targetPicker, title: selectedTarget.rawValue)

        swapButton.setImage(UIImage(systemName: "arrow.left.arrow.right"), for: .normal)
        swapButton.tintColor = UIColor(red: 0.4, green: 0.8, blue: 1.0, alpha: 1)
        swapButton.translatesAutoresizingMaskIntoConstraints = false
        swapButton.addTarget(self, action: #selector(swapLanguages), for: .touchUpInside)

        sourcePicker.menu = buildLanguageMenu(for: .source)
        sourcePicker.showsMenuAsPrimaryAction = true
        targetPicker.menu = buildLanguageMenu(for: .target)
        targetPicker.showsMenuAsPrimaryAction = true

        langStackView.addArrangedSubview(sourcePicker)
        langStackView.addArrangedSubview(swapButton)
        langStackView.addArrangedSubview(targetPicker)
    }

    private func configurePickerButton(_ button: UIButton, title: String) {
        var config = UIButton.Configuration.filled()
        config.title = title
        config.baseForegroundColor = .white
        config.baseBackgroundColor = UIColor.white.withAlphaComponent(0.12)
        config.cornerStyle = .capsule
        config.contentInsets = NSDirectionalEdgeInsets(top: 8, leading: 14, bottom: 8, trailing: 14)
        config.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { attrs in
            var a = attrs
            a.font = UIFont.systemFont(ofSize: 13, weight: .semibold)
            return a
        }
        button.configuration = config
        button.translatesAutoresizingMaskIntoConstraints = false
    }

    private enum PickerSide { case source, target }

    private func buildLanguageMenu(for side: PickerSide) -> UIMenu {
        let actions = LanguageOption.allCases.map { lang in
            UIAction(title: lang.rawValue) { [weak self] _ in
                guard let self else { return }
                if side == .source {
                    self.selectedSource = lang
                    self.configurePickerButton(self.sourcePicker, title: lang.rawValue)
                } else {
                    self.selectedTarget = lang
                    self.configurePickerButton(self.targetPicker, title: lang.rawValue)
                }
                self.pipManager.updateLanguage(from: self.selectedSource.code, to: self.selectedTarget.code)
            }
        }
        return UIMenu(children: actions)
    }

    @objc private func swapLanguages() {
        let temp = selectedSource
        selectedSource = selectedTarget
        selectedTarget = temp
        configurePickerButton(sourcePicker, title: selectedSource.rawValue)
        configurePickerButton(targetPicker, title: selectedTarget.rawValue)
        pipManager.updateLanguage(from: selectedSource.code, to: selectedTarget.code)

        UIView.animate(withDuration: 0.3, delay: 0, usingSpringWithDamping: 0.7, initialSpringVelocity: 0.5) {
            self.swapButton.transform = CGAffineTransform(rotationAngle: .pi)
        } completion: { _ in
            UIView.animate(withDuration: 0.3) {
                self.swapButton.transform = .identity
            }
        }
    }

    private func setupStatusCard() {
        statusCard.backgroundColor = UIColor.white.withAlphaComponent(0.06)
        statusCard.layer.cornerRadius = 12
        statusCard.layer.borderColor = UIColor.white.withAlphaComponent(0.1).cgColor
        statusCard.layer.borderWidth = 0.5
        statusCard.translatesAutoresizingMaskIntoConstraints = false

        statusLabel.text = "⬤  พร้อมใช้งาน"
        statusLabel.font = .systemFont(ofSize: 13, weight: .medium)
        statusLabel.textColor = UIColor(red: 0.4, green: 0.8, blue: 1.0, alpha: 1)
        statusLabel.textAlignment = .center
        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        statusCard.addSubview(statusLabel)
    }

    private func setupTextViews() {
        [originalTextView, translatedTextView].forEach { tv in
            tv.backgroundColor = UIColor.white.withAlphaComponent(0.06)
            tv.layer.cornerRadius = 12
            tv.layer.borderColor = UIColor.white.withAlphaComponent(0.1).cgColor
            tv.layer.borderWidth = 0.5
            tv.textColor = .white
            tv.isEditable = false
            tv.font = .systemFont(ofSize: 15)
            tv.textContainerInset = UIEdgeInsets(top: 12, left: 12, bottom: 12, right: 12)
            tv.translatesAutoresizingMaskIntoConstraints = false
        }
        originalTextView.textColor = UIColor.white.withAlphaComponent(0.7)
        originalTextView.font = .systemFont(ofSize: 13)
        originalTextView.text = "ข้อความต้นฉบับจะปรากฎที่นี่..."
        translatedTextView.text = "คำแปลจะปรากฎที่นี่..."
    }

    private func setupButtons() {
        var startConfig = UIButton.Configuration.filled()
        startConfig.title = "เริ่มแปลเสียง"
        startConfig.image = UIImage(systemName: "waveform.circle.fill")
        startConfig.imagePadding = 8
        startConfig.baseBackgroundColor = UIColor(red: 0.2, green: 0.6, blue: 1.0, alpha: 1)
        startConfig.baseForegroundColor = .white
        startConfig.cornerStyle = .capsule
        startConfig.contentInsets = NSDirectionalEdgeInsets(top: 16, leading: 32, bottom: 16, trailing: 32)
        startConfig.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { attrs in
            var a = attrs
            a.font = UIFont.systemFont(ofSize: 17, weight: .bold)
            return a
        }
        startStopButton.configuration = startConfig
        startStopButton.translatesAutoresizingMaskIntoConstraints = false
        startStopButton.addTarget(self, action: #selector(toggleCapture), for: .touchUpInside)

        var pipConfig = UIButton.Configuration.tinted()
        pipConfig.title = "เปิด PiP"
        pipConfig.image = UIImage(systemName: "pip.fill")
        pipConfig.imagePadding = 6
        pipConfig.baseForegroundColor = UIColor(red: 0.4, green: 0.8, blue: 1.0, alpha: 1)
        pipConfig.cornerStyle = .capsule
        pipConfig.contentInsets = NSDirectionalEdgeInsets(top: 12, leading: 20, bottom: 12, trailing: 20)
        pipButton.configuration = pipConfig
        pipButton.translatesAutoresizingMaskIntoConstraints = false
        pipButton.addTarget(self, action: #selector(togglePiP), for: .touchUpInside)
    }

    private func layoutAll() {
        let scrollView = UIScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scrollView)

        let contentStack = UIStackView(arrangedSubviews: [
            titleLabel,
            subtitleLabel,
            langStackView,
            statusCard,
            makeSectionLabel("ต้นฉบับ"),
            originalTextView,
            makeSectionLabel("คำแปล"),
            translatedTextView,
            startStopButton,
            pipButton
        ])
        contentStack.axis = .vertical
        contentStack.spacing = 14
        contentStack.translatesAutoresizingMaskIntoConstraints = false
        contentStack.setCustomSpacing(4, after: titleLabel)
        contentStack.setCustomSpacing(20, after: subtitleLabel)
        contentStack.setCustomSpacing(6, after: makeSectionLabel("ต้นฉบับ"))
        contentStack.setCustomSpacing(6, after: makeSectionLabel("คำแปล"))
        contentStack.setCustomSpacing(20, after: translatedTextView)

        scrollView.addSubview(contentStack)

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),

            contentStack.topAnchor.constraint(equalTo: scrollView.topAnchor, constant: 24),
            contentStack.bottomAnchor.constraint(equalTo: scrollView.bottomAnchor, constant: -24),
            contentStack.leadingAnchor.constraint(equalTo: scrollView.leadingAnchor, constant: 20),
            contentStack.trailingAnchor.constraint(equalTo: scrollView.trailingAnchor, constant: -20),
            contentStack.widthAnchor.constraint(equalTo: scrollView.widthAnchor, constant: -40),

            statusLabel.topAnchor.constraint(equalTo: statusCard.topAnchor, constant: 10),
            statusLabel.bottomAnchor.constraint(equalTo: statusCard.bottomAnchor, constant: -10),
            statusLabel.leadingAnchor.constraint(equalTo: statusCard.leadingAnchor, constant: 16),
            statusLabel.trailingAnchor.constraint(equalTo: statusCard.trailingAnchor, constant: -16),

            originalTextView.heightAnchor.constraint(equalToConstant: 80),
            translatedTextView.heightAnchor.constraint(equalToConstant: 110),

            startStopButton.heightAnchor.constraint(equalToConstant: 56),
            pipButton.heightAnchor.constraint(equalToConstant: 48)
        ])
    }

    private func makeSectionLabel(_ text: String) -> UILabel {
        let label = UILabel()
        label.text = text
        label.font = .systemFont(ofSize: 12, weight: .semibold)
        label.textColor = UIColor.white.withAlphaComponent(0.4)
        label.textAlignment = .left
        return label
    }

    private func setupOrchestrator() {
        orchestrator.delegate = self
    }

    private func setupPiP() {
        pipManager.setup()
        pipManager.updateLanguage(from: selectedSource.code, to: selectedTarget.code)
        pipManager.onPiPActiveChange = { [weak self] active in
            DispatchQueue.main.async {
                var config = self?.pipButton.configuration
                config?.title = active ? "ปิด PiP" : "เปิด PiP"
                config?.image = UIImage(systemName: active ? "pip.exit" : "pip.fill")
                self?.pipButton.configuration = config
            }
        }
    }

    @objc private func toggleCapture() {
        if isRunning {
            orchestrator.stop()
        } else {
            orchestrator.sourceLanguage = selectedSource
            orchestrator.targetLanguage = selectedTarget
            orchestrator.start()
        }
    }

    @objc private func togglePiP() {
        if pipManager.isPiPActive {
            pipManager.stopPiP()
        } else {
            pipManager.startPiP()
        }
    }

    private func updateStartButton(running: Bool) {
        var config = startStopButton.configuration
        if running {
            config?.title = "หยุดการแปล"
            config?.image = UIImage(systemName: "stop.circle.fill")
            config?.baseBackgroundColor = UIColor(red: 0.9, green: 0.3, blue: 0.3, alpha: 1)
        } else {
            config?.title = "เริ่มแปลเสียง"
            config?.image = UIImage(systemName: "waveform.circle.fill")
            config?.baseBackgroundColor = UIColor(red: 0.2, green: 0.6, blue: 1.0, alpha: 1)
        }
        startStopButton.configuration = config
    }
}

extension ViewController: TranslationOrchestratorDelegate {
    func orchestrator(_ orchestrator: TranslationOrchestrator, didUpdateOriginal text: String) {
        originalTextView.text = text
    }

    func orchestrator(_ orchestrator: TranslationOrchestrator, didUpdateTranslation text: String) {
        translatedTextView.text = text
        pipManager.update(original: orchestrator.sourceLanguage.rawValue, translated: text)
    }

    func orchestratorDidStart(_ orchestrator: TranslationOrchestrator) {
        isRunning = true
        updateStartButton(running: true)
        statusLabel.text = "⬤  กำลังแปลเสียง..."
        statusLabel.textColor = UIColor(red: 0.3, green: 1.0, blue: 0.5, alpha: 1)
        pipManager.setListening(true)
        pipManager.startPiP()
    }

    func orchestratorDidStop(_ orchestrator: TranslationOrchestrator) {
        isRunning = false
        updateStartButton(running: false)
        statusLabel.text = "⬤  หยุดการทำงาน"
        statusLabel.textColor = UIColor(red: 0.4, green: 0.8, blue: 1.0, alpha: 1)
        pipManager.setListening(false)
    }

    func orchestrator(_ orchestrator: TranslationOrchestrator, didFailWithError error: Error) {
        DispatchQueue.main.async { [weak self] in
            self?.statusLabel.text = "⚠️  \(error.localizedDescription)"
            self?.statusLabel.textColor = UIColor(red: 1.0, green: 0.6, blue: 0.3, alpha: 1)
        }
    }
}
