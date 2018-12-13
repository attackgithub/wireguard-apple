// SPDX-License-Identifier: MIT
// Copyright © 2018 WireGuard LLC. All Rights Reserved.

import UIKit
import os.log

class SettingsTableViewController: UITableViewController {

    enum SettingsFields: String {
        case iosAppVersion = "WireGuard for iOS"
        case goBackendVersion = "WireGuard Go Backend"
        case exportZipArchive = "Export zip archive"
        case exportLogFile = "Export log file"
    }

    let settingsFieldsBySection: [[SettingsFields]] = [
        [.iosAppVersion, .goBackendVersion],
        [.exportZipArchive],
        [.exportLogFile]
    ]

    let tunnelsManager: TunnelsManager?
    var wireguardCaptionedImage: (view: UIView, size: CGSize)?

    init(tunnelsManager: TunnelsManager?) {
        self.tunnelsManager = tunnelsManager
        super.init(style: .grouped)
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Settings"
        navigationItem.rightBarButtonItem = UIBarButtonItem(barButtonSystemItem: .done, target: self, action: #selector(doneTapped))

        tableView.estimatedRowHeight = 44
        tableView.rowHeight = UITableView.automaticDimension
        tableView.allowsSelection = false

        tableView.register(KeyValueCell.self)
        tableView.register(ButtonCell.self)

        tableView.tableFooterView = UIImageView(image: UIImage(named: "wireguard.pdf"))
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        guard let logo = self.tableView.tableFooterView else { return }
        
        let bottomPadding = max(tableView.layoutMargins.bottom, 10)
        let fullHeight = max(tableView.contentSize.height, tableView.bounds.size.height - tableView.layoutMargins.top - bottomPadding)
        
        let imageAspectRatio = logo.intrinsicContentSize.width / logo.intrinsicContentSize.height
        
        var height = tableView.estimatedRowHeight * 1.5
        var width = height * imageAspectRatio
        let maxWidth = view.bounds.size.width - max(tableView.layoutMargins.left + tableView.layoutMargins.right, 20)
        if width > maxWidth {
            width = maxWidth
            height = width / imageAspectRatio
        }
        
        let needsReload = height != logo.frame.height
        
        logo.frame = CGRect(x: (view.bounds.size.width - width) / 2, y: fullHeight - height, width: width, height: height)
        
        if needsReload {
            tableView.tableFooterView = logo
        }
    }

    @objc func doneTapped() {
        dismiss(animated: true, completion: nil)
    }

    func exportConfigurationsAsZipFile(sourceView: UIView) {
        guard let tunnelsManager = tunnelsManager else { return }
        guard let destinationDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else { return }

        let destinationURL = destinationDir.appendingPathComponent("wireguard-export.zip")
        _ = FileManager.deleteFile(at: destinationURL)

        let count = tunnelsManager.numberOfTunnels()
        let tunnelConfigurations = (0 ..< count).compactMap { tunnelsManager.tunnel(at: $0).tunnelConfiguration() }
        ZipExporter.exportConfigFiles(tunnelConfigurations: tunnelConfigurations, to: destinationURL) { [weak self] error in
            if let error = error {
                ErrorPresenter.showErrorAlert(error: error, from: self)
                return
            }

            let fileExportVC = UIDocumentPickerViewController(url: destinationURL, in: .exportToService)
            self?.present(fileExportVC, animated: true, completion: nil)
        }
    }

    func exportLogForLastActivatedTunnel(sourceView: UIView) {
        guard let destinationDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else { return }

        let dateFormatter = ISO8601DateFormatter()
        dateFormatter.formatOptions = [.withFullDate, .withTime, .withTimeZone] // Avoid ':' in the filename
        let timeStampString = dateFormatter.string(from: Date())
        let destinationURL = destinationDir.appendingPathComponent("wireguard-log-\(timeStampString).txt")

        DispatchQueue.global(qos: .userInitiated).async {

            if FileManager.default.fileExists(atPath: destinationURL.path) {
                let isDeleted = FileManager.deleteFile(at: destinationURL)
                if !isDeleted {
                    ErrorPresenter.showErrorAlert(title: "Log export failed", message: "The pre-existing log could not be cleared", from: self)
                    return
                }
            }

            guard let networkExtensionLogFilePath = FileManager.networkExtensionLogFileURL?.path else {
                ErrorPresenter.showErrorAlert(title: "Log export failed", message: "Internal error obtaining extension log path", from: self)
                return
            }

            let isWritten = Logger.writeLog(mergedWith: networkExtensionLogFilePath, tag: "APP", otherTag: "EXT", to: destinationURL.path)
            guard isWritten else {
                ErrorPresenter.showErrorAlert(title: "Log export failed", message: "Internal error merging logs", from: self)
                return
            }

            DispatchQueue.main.async {
                let activityVC = UIActivityViewController(activityItems: [destinationURL], applicationActivities: nil)
                // popoverPresentationController shall be non-nil on the iPad
                activityVC.popoverPresentationController?.sourceView = sourceView
                activityVC.popoverPresentationController?.sourceRect = sourceView.bounds
                activityVC.completionWithItemsHandler = { _, _, _, _ in
                    // Remove the exported log file after the activity has completed
                    _ = FileManager.deleteFile(at: destinationURL)
                }
                self.present(activityVC, animated: true)
            }
        }
    }
}

// MARK: UITableViewDataSource

extension SettingsTableViewController {
    override func numberOfSections(in tableView: UITableView) -> Int {
        return settingsFieldsBySection.count
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return settingsFieldsBySection[section].count
    }

    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        switch section {
        case 0:
            return "About"
        case 1:
            return "Export configurations"
        case 2:
            return "Tunnel log"
        default:
            return nil
        }
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let field = settingsFieldsBySection[indexPath.section][indexPath.row]
        if field == .iosAppVersion || field == .goBackendVersion {
            let cell: KeyValueCell = tableView.dequeueReusableCell(for: indexPath)
            cell.key = field.rawValue
            if field == .iosAppVersion {
                var appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Unknown version"
                if let appBuild = Bundle.main.infoDictionary?["CFBundleVersion"] as? String {
                    appVersion += " (\(appBuild))"
                }
                cell.value = appVersion
            } else if field == .goBackendVersion {
                cell.value = WIREGUARD_GO_VERSION
            }
            return cell
        } else if field == .exportZipArchive {
            let cell: ButtonCell = tableView.dequeueReusableCell(for: indexPath)
            cell.buttonText = field.rawValue
            cell.onTapped = { [weak self] in
                self?.exportConfigurationsAsZipFile(sourceView: cell.button)
            }
            return cell
        } else {
            assert(field == .exportLogFile)
            let cell: ButtonCell = tableView.dequeueReusableCell(for: indexPath)
            cell.buttonText = field.rawValue
            cell.onTapped = { [weak self] in
                self?.exportLogForLastActivatedTunnel(sourceView: cell.button)
            }
            return cell
        }
    }
}

private class KeyValueCell: UITableViewCell {
    var key: String {
        get { return textLabel?.text ?? "" }
        set(value) { textLabel?.text = value }
    }
    var value: String {
        get { return detailTextLabel?.text ?? "" }
        set(value) { detailTextLabel?.text = value }
    }

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: .value1, reuseIdentifier: KeyValueCell.reuseIdentifier)
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        key = ""
        value = ""
    }
}

private class ButtonCell: UITableViewCell {
    var buttonText: String {
        get { return button.title(for: .normal) ?? "" }
        set(value) { button.setTitle(value, for: .normal) }
    }
    var onTapped: (() -> Void)?

    let button: UIButton

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        button = UIButton(type: .system)
        button.titleLabel?.font = UIFont.preferredFont(forTextStyle: .body)
        button.titleLabel?.adjustsFontForContentSizeCategory = true
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        contentView.addSubview(button)
        button.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            button.topAnchor.constraint(equalTo: contentView.layoutMarginsGuide.topAnchor),
            contentView.layoutMarginsGuide.bottomAnchor.constraint(equalTo: button.bottomAnchor),
            button.centerXAnchor.constraint(equalTo: contentView.centerXAnchor)
        ])
        button.addTarget(self, action: #selector(buttonTapped), for: .touchUpInside)
    }

    @objc func buttonTapped() {
        onTapped?()
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        buttonText = ""
        onTapped = nil
    }
}
