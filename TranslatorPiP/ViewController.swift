import UIKit
import AVKit
import ReplayKit

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
    private let broadcastButton = UIButton(type: .system)
    private let pipButton = UIButton(type: .system)
    private let langStackView = UIStackView()
    private let sourcePicker = UIButton(type: .system)
    private let targetPicker = UIButton(type: .system)
    private let swapButton = UIButton(type: .system)

    /// Nearly-invisible RPSystemBroadcastPickerView overlaid on broadcastButton.
    /// Tapping broadcastButton simulates a tap here → iOS shows the extension picker.
    private lazy var sysBroadcastPicker: RPSystemBroadcastPickerView = {
        let v = RPSystemBroadcastPickerView(frame: .zero)
        v.preferredExtension = nil      // show ALL registered broadcast extensions
        v.showsMicrophoneButton = false
        v.alpha = 0.011                 // nearly invisible but still hittable
        v.translatesAutoresizingMaskIntoConstraints = false
        return v
    }()

    private var selectedSource: LanguageOption = .english
    private var selectedTarget: LanguageOption = .thai
    private var isRunning = false

    // MARK: — Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        setupGradientBackground()
        setupUI()
        orchestrator.delegate = self
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        pipManager.setup(sourceView: view)
        pipManager.updateLanguage(from: selectedSource.code, to: selectedTarget.code)
        pipManager.onPiPActiveChange = { [weak self] active in
            DispatchQueue.main.async {
                var c = self?.pipButton.configuration
                c?.title = active ? "ปิด PiP" : "เปิด PiP"
                c?.image = UIImage(systemName: active ? "pip.exit" : "pip.fill")
                self?.pipButton.configuration = c
            }
        }
    }

    // MARK: — Background

    private func setupGradientBackground() {
        let g = CAGradientLayer()
        g.colors = [
            UIColor(red: 0.06, green: 0.06, blue: 0.14, alpha: 1).cgColor,
            UIColor(red: 0.08, green: 0.08, blue: 0.20, alpha: 1).cgColor
        ]
        g.startPoint = CGPoint(x: 0, y: 0)
        g.endPoint   = CGPoint(x: 1, y: 1)
        g.frame = view.bounds
        view.layer.insertSublayer(g, at: 0)
    }

    // MARK: — UI Setup

    private func setupUI() {
        titleLabel.text = "TranslatorPiP"
        titleLabel.font = .systemFont(ofSize: 28, weight: .bold)
        titleLabel.textColor = .white
        titleLabel.textAlignment = .center
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        subtitleLabel.text = "แปลเสียงภายในเครื่องแบบ Real-time"
        subtitleLabel.font = .systemFont(ofSize: 14)
        subtitleLabel.textColor = UIColor.white.withAlphaComponent(0.55)
        subtitleLabel.textAlignment = .center
        subtitleLabel.translatesAutoresizingMaskIntoConstraints = false

        setupLanguagePicker()
        setupStatusCard()
        setupTextViews()
        setupButtons()
        layoutAll()
    }

    // MARK: — Language picker

    private func setupLanguagePicker() {
        langStackView.axis = .horizontal
        langStackView.spacing = 8
        langStackView.alignment = .center
        langStackView.distribution = .fill
        langStackView.translatesAutoresizingMaskIntoConstraints = false

        configurePickerButton(sourcePicker, title: selectedSource.rawValue)
        configurePickerButton(targetPicker, title: selectedTarget.rawValue)
        sourcePicker.menu = buildLanguageMenu(for: .source)
        sourcePicker.showsMenuAsPrimaryAction = true
        targetPicker.menu = buildLanguageMenu(for: .target)
        targetPicker.showsMenuAsPrimaryAction = true

        swapButton.setImage(UIImage(systemName: "arrow.left.arrow.right"), for: .normal)
        swapButton.tintColor = UIColor(red: 0.4, green: 0.8, blue: 1.0, alpha: 1)
        swapButton.translatesAutoresizingMaskIntoConstraints = false
        swapButton.addTarget(self, action: #selector(swapLanguages), for: .touchUpInside)

        langStackView.addArrangedSubview(sourcePicker)
        langStackView.addArrangedSubview(swapButton)
        langStackView.addArrangedSubview(targetPicker)
    }

    private func configurePickerButton(_ button: UIButton, title: String) {
        var c = UIButton.Configuration.filled()
        c.title = title
        c.baseForegroundColor = .white
        c.baseBackgroundColor = UIColor.white.withAlphaComponent(0.12)
        c.cornerStyle = .capsule
        c.contentInsets = NSDirectionalEdgeInsets(top: 8, leading: 14, bottom: 8, trailing: 14)
        c.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { a in
            var a = a; a.font = .systemFont(ofSize: 13, weight: .semibold); return a
        }
        button.configuration = c
        button.translatesAutoresizingMaskIntoConstraints = false
    }

    private enum PickerSide { case source, target }

    private func buildLanguageMenu(for side: PickerSide) -> UIMenu {
        let actions = LanguageOption.allCases.map { lang in
            UIAction(title: lang.rawValue) { [weak self] _ in
                guard let self else { return }
                if side == .source { self.selectedSource = lang; self.configurePickerButton(self.sourcePicker, title: lang.rawValue) }
                else               { self.selectedTarget = lang; self.configurePickerButton(self.targetPicker, title: lang.rawValue) }
                self.pipManager.updateLanguage(from: self.selectedSource.code, to: self.selectedTarget.code)
            }
        }
        return UIMenu(children: actions)
    }

    @objc private func swapLanguages() {
        swap(&selectedSource, &selectedTarget)
        configurePickerButton(sourcePicker, title: selectedSource.rawValue)
        configurePickerButton(targetPicker, title: selectedTarget.rawValue)
        pipManager.updateLanguage(from: selectedSource.code, to: selectedTarget.code)
        UIView.animate(withDuration: 0.3, delay: 0, usingSpringWithDamping: 0.7, initialSpringVelocity: 0.5) {
            self.swapButton.transform = CGAffineTransform(rotationAngle: .pi)
        } completion: { _ in UIView.animate(withDuration: 0.3) { self.swapButton.transform = .identity } }
    }

    // MARK: — Status card

    private func setupStatusCard() {
        statusCard.backgroundColor = UIColor.white.withAlphaComponent(0.06)
        statusCard.layer.cornerRadius = 12
        statusCard.layer.borderColor = UIColor.white.withAlphaComponent(0.1).cgColor
        statusCard.layer.borderWidth = 0.5
        statusCard.translatesAutoresizingMaskIntoConstraints = false

        statusLabel.text = "⬤  กด \"เริ่มแปลเสียง\" แล้วกดปุ่มสีส้ม 📡 เพื่อเลือก Extension"
        statusLabel.font = .systemFont(ofSize: 13, weight: .medium)
        statusLabel.textColor = UIColor(red: 0.4, green: 0.8, blue: 1.0, alpha: 1)
        statusLabel.textAlignment = .center
        statusLabel.numberOfLines = 0
        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        statusCard.addSubview(statusLabel)
    }

    // MARK: — Text views

    private func setupTextViews() {
        for tv in [originalTextView, translatedTextView] {
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

    // MARK: — Buttons

    private func setupButtons() {
        // Start / Stop
        var sc = UIButton.Configuration.filled()
        sc.title = "เริ่มแปลเสียง"
        sc.image = UIImage(systemName: "waveform.circle.fill")
        sc.imagePadding = 8
        sc.baseBackgroundColor = UIColor(red: 0.2, green: 0.6, blue: 1.0, alpha: 1)
        sc.baseForegroundColor = .white
        sc.cornerStyle = .capsule
        sc.contentInsets = NSDirectionalEdgeInsets(top: 16, leading: 32, bottom: 16, trailing: 32)
        sc.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { a in
            var a = a; a.font = .systemFont(ofSize: 17, weight: .bold); return a
        }
        startStopButton.configuration = sc
        startStopButton.translatesAutoresizingMaskIntoConstraints = false
        startStopButton.addTarget(self, action: #selector(toggleCapture), for: .touchUpInside)

        // Broadcast picker button — orange, tappable, with invisible RPSystemBroadcastPickerView on top
        var bc = UIButton.Configuration.filled()
        bc.title = "📡  เปิดรับเสียงภายในเครื่อง"
        bc.baseBackgroundColor = UIColor(red: 1.0, green: 0.55, blue: 0.1, alpha: 1)
        bc.baseForegroundColor = .white
        bc.cornerStyle = .capsule
        bc.contentInsets = NSDirectionalEdgeInsets(top: 14, leading: 24, bottom: 14, trailing: 24)
        bc.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { a in
            var a = a; a.font = .systemFont(ofSize: 15, weight: .semibold); return a
        }
        broadcastButton.configuration = bc
        broadcastButton.translatesAutoresizingMaskIntoConstraints = false
        broadcastButton.addTarget(self, action: #selector(triggerBroadcastPicker), for: .touchUpInside)

        // PiP
        var pc = UIButton.Configuration.tinted()
        pc.title = "เปิด PiP"
        pc.image = UIImage(systemName: "pip.fill")
        pc.imagePadding = 6
        pc.baseForegroundColor = UIColor(red: 0.4, green: 0.8, blue: 1.0, alpha: 1)
        pc.cornerStyle = .capsule
        pc.contentInsets = NSDirectionalEdgeInsets(top: 12, leading: 20, bottom: 12, trailing: 20)
        pipButton.configuration = pc
        pipButton.translatesAutoresizingMaskIntoConstraints = false
        pipButton.addTarget(self, action: #selector(togglePiP), for: .touchUpInside)
    }

    // MARK: — Layout

    private func layoutAll() {
        let scrollView = UIScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scrollView)

        let hintLabel = UILabel()
        hintLabel.text = "กด 📡 → เลือก \"TranslatorPiP\" จาก picker → กด Start Broadcast\nจากนั้นกด \"เปิด PiP\" แล้วสลับไปแอพที่ต้องการแปล"
        hintLabel.font = .systemFont(ofSize: 12)
        hintLabel.textColor = UIColor.white.withAlphaComponent(0.45)
        hintLabel.numberOfLines = 0
        hintLabel.textAlignment = .center
        hintLabel.translatesAutoresizingMaskIntoConstraints = false

        // Container: styled broadcastButton + invisible sysBroadcastPicker on top
        let broadcastContainer = UIView()
        broadcastContainer.translatesAutoresizingMaskIntoConstraints = false
        broadcastContainer.addSubview(broadcastButton)
        broadcastContainer.addSubview(sysBroadcastPicker)

        NSLayoutConstraint.activate([
            broadcastButton.topAnchor.constraint(equalTo: broadcastContainer.topAnchor),
            broadcastButton.bottomAnchor.constraint(equalTo: broadcastContainer.bottomAnchor),
            broadcastButton.leadingAnchor.constraint(equalTo: broadcastContainer.leadingAnchor),
            broadcastButton.trailingAnchor.constraint(equalTo: broadcastContainer.trailingAnchor),
            broadcastButton.heightAnchor.constraint(equalToConstant: 52),

            sysBroadcastPicker.topAnchor.constraint(equalTo: broadcastContainer.topAnchor),
            sysBroadcastPicker.bottomAnchor.constraint(equalTo: broadcastContainer.bottomAnchor),
            sysBroadcastPicker.leadingAnchor.constraint(equalTo: broadcastContainer.leadingAnchor),
            sysBroadcastPicker.trailingAnchor.constraint(equalTo: broadcastContainer.trailingAnchor),
        ])

        let stack = UIStackView(arrangedSubviews: [
            titleLabel,
            subtitleLabel,
            langStackView,
            statusCard,
            makeSectionLabel("ต้นฉบับ"),
            originalTextView,
            makeSectionLabel("คำแปล"),
            translatedTextView,
            startStopButton,
            broadcastContainer,
            hintLabel,
            pipButton,
        ])
        stack.axis = .vertical
        stack.spacing = 14
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.setCustomSpacing(4,  after: titleLabel)
        stack.setCustomSpacing(20, after: subtitleLabel)
        stack.setCustomSpacing(20, after: translatedTextView)
        stack.setCustomSpacing(8,  after: broadcastContainer)
        stack.setCustomSpacing(16, after: hintLabel)

        scrollView.addSubview(stack)

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),

            stack.topAnchor.constraint(equalTo: scrollView.topAnchor, constant: 24),
            stack.bottomAnchor.constraint(equalTo: scrollView.bottomAnchor, constant: -24),
            stack.leadingAnchor.constraint(equalTo: scrollView.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: scrollView.trailingAnchor, constant: -20),
            stack.widthAnchor.constraint(equalTo: scrollView.widthAnchor, constant: -40),

            statusLabel.topAnchor.constraint(equalTo: statusCard.topAnchor, constant: 10),
            statusLabel.bottomAnchor.constraint(equalTo: statusCard.bottomAnchor, constant: -10),
            statusLabel.leadingAnchor.constraint(equalTo: statusCard.leadingAnchor, constant: 16),
            statusLabel.trailingAnchor.constraint(equalTo: statusCard.trailingAnchor, constant: -16),

            originalTextView.heightAnchor.constraint(equalToConstant: 80),
            translatedTextView.heightAnchor.constraint(equalToConstant: 110),
            startStopButton.heightAnchor.constraint(equalToConstant: 56),
            pipButton.heightAnchor.constraint(equalToConstant: 48),
        ])
    }

    private func makeSectionLabel(_ text: String) -> UILabel {
        let l = UILabel()
        l.text = text
        l.font = .systemFont(ofSize: 12, weight: .semibold)
        l.textColor = UIColor.white.withAlphaComponent(0.4)
        return l
    }

    // MARK: — Actions

    @objc private func toggleCapture() {
        if isRunning {
            orchestrator.stop()
        } else {
            orchestrator.sourceLanguage = selectedSource
            orchestrator.targetLanguage = selectedTarget
            orchestrator.start()
        }
    }

    /// Simulate a tap on the hidden RPSystemBroadcastPickerView so iOS shows
    /// the broadcast extension picker popup — user selects TranslatorPiP.
    @objc private func triggerBroadcastPicker() {
        for subview in sysBroadcastPicker.subviews {
            if let btn = subview as? UIButton {
                btn.sendActions(for: .touchUpInside)
                return
            }
        }
    }

    @objc private func togglePiP() {
        if pipManager.isPiPActive { pipManager.stopPiP() }
        else { pipManager.startPiP() }
    }

    private func updateStartButton(running: Bool) {
        var c = startStopButton.configuration
        if running {
            c?.title = "หยุดการแปล"
            c?.image = UIImage(systemName: "stop.circle.fill")
            c?.baseBackgroundColor = UIColor(red: 0.9, green: 0.3, blue: 0.3, alpha: 1)
        } else {
            c?.title = "เริ่มแปลเสียง"
            c?.image = UIImage(systemName: "waveform.circle.fill")
            c?.baseBackgroundColor = UIColor(red: 0.2, green: 0.6, blue: 1.0, alpha: 1)
        }
        startStopButton.configuration = c
    }
}

// MARK: — TranslationOrchestratorDelegate

extension ViewController: TranslationOrchestratorDelegate {
    func orchestrator(_ orchestrator: TranslationOrchestrator, didUpdateOriginal text: String) {
        originalTextView.text = text
    }

    func orchestrator(_ orchestrator: TranslationOrchestrator, didUpdateTranslation text: String) {
        translatedTextView.text = text
        pipManager.update(original: orchestrator.sourceLanguage.rawValue, translated: text)
    }

    func orchestratorDidStart(_ orchestrator: TranslationOrchestrator, strategy: ScreenAudioCapture.Strategy) {
        isRunning = true
        updateStartButton(running: true)
        pipManager.setListening(true)
        statusLabel.text = "⬤  รอ Broadcast... กด 📡 เลือก \"TranslatorPiP\" แล้ว Start Broadcast"
        statusLabel.textColor = UIColor(red: 1.0, green: 0.85, blue: 0.4, alpha: 1)
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
