import AppKit

class AdjustableValueControl: NSView {
  private let decrementButton = NSButton()
  private let incrementButton = NSButton()
  private let label = NSTextField()

  private let title: String
  private let minValue: Double
  private let maxValue: Double
  private let step: Double
  private let formatter: (Double) -> String
  private let getValue: () -> Double
  private let setValue: (Double) -> Void

  init(
    title: String,
    minValue: Double,
    maxValue: Double,
    step: Double,
    formatter: @escaping (Double) -> String,
    getValue: @escaping () -> Double,
    setValue: @escaping (Double) -> Void
  ) {
    self.title = title
    self.minValue = minValue
    self.maxValue = maxValue
    self.step = step
    self.formatter = formatter
    self.getValue = getValue
    self.setValue = setValue

    super.init(frame: .zero)
    setupUI()
    refresh()
  }

  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  private func setupUI() {
    let buttonSize: CGFloat = 30
    let buttonSpacing: CGFloat = 4
    let viewHeight: CGFloat = 22
    let viewWidth: CGFloat = 220
    let leftPadding: CGFloat = 14
    let rightPadding: CGFloat = -8

    frame = NSRect(x: 0, y: 0, width: viewWidth, height: viewHeight)

    setupLabel()
    setupButton(decrementButton, title: "−", action: #selector(decrementValue))
    setupButton(incrementButton, title: "+", action: #selector(incrementValue))

    let buttonStack = NSStackView(views: [decrementButton, incrementButton])
    buttonStack.orientation = .horizontal
    buttonStack.spacing = buttonSpacing
    buttonStack.translatesAutoresizingMaskIntoConstraints = false
    addSubview(buttonStack)

    NSLayoutConstraint.activate([
      decrementButton.widthAnchor.constraint(equalToConstant: buttonSize),
      decrementButton.heightAnchor.constraint(equalToConstant: buttonSize),
      incrementButton.widthAnchor.constraint(equalToConstant: buttonSize),
      incrementButton.heightAnchor.constraint(equalToConstant: buttonSize),

      label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: leftPadding),
      label.centerYAnchor.constraint(equalTo: centerYAnchor),

      buttonStack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: rightPadding),
      buttonStack.centerYAnchor.constraint(equalTo: centerYAnchor),

      label.trailingAnchor.constraint(lessThanOrEqualTo: buttonStack.leadingAnchor, constant: -8),
    ])
  }

  private func setupButton(_ button: NSButton, title: String, action: Selector) {
    button.title = title
    button.bezelStyle = .roundRect
    button.target = self
    button.action = action
    button.font = .systemFont(ofSize: 14)
    button.setButtonType(.momentaryPushIn)
    button.translatesAutoresizingMaskIntoConstraints = false
    button.focusRingType = .none
  }

  private func setupLabel() {
    label.isEditable = false
    label.isBordered = false
    label.drawsBackground = false
    label.alignment = .left
    label.font = .menuFont(ofSize: 0)
    label.translatesAutoresizingMaskIntoConstraints = false
    addSubview(label)
  }

  private func clampedValue(_ value: Double) -> Double {
    min(max(value, minValue), maxValue)
  }

  private func steppedValue(_ value: Double) -> Double {
    (value / step).rounded() * step
  }

  private func applyDelta(_ delta: Double) {
    let currentValue = getValue()
    let nextValue = steppedValue(clampedValue(currentValue + delta))
    setValue(nextValue)
    refresh()
  }

  @objc private func decrementValue() {
    applyDelta(-step)
  }

  @objc private func incrementValue() {
    applyDelta(step)
  }

  func refresh() {
    let currentValue = clampedValue(getValue())
    label.stringValue = "\(title): \(formatter(currentValue))"
    decrementButton.isEnabled = currentValue > minValue
    incrementButton.isEnabled = currentValue < maxValue
  }
}
