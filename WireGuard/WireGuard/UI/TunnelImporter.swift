// SPDX-License-Identifier: MIT
// Copyright © 2018-2019 WireGuard LLC. All Rights Reserved.

import Foundation

class TunnelImporter {
    static func importFromFile(url: URL, into tunnelsManager: TunnelsManager, sourceVC: AnyObject?, errorPresenterType: ErrorPresenterProtocol.Type, completionHandler: (() -> Void)? = nil) {
        if url.pathExtension == "zip" {
            ZipImporter.importConfigFiles(from: url) { result in
                if let error = result.error {
                    errorPresenterType.showErrorAlert(error: error, from: sourceVC)
                    return
                }
                let configs = result.value!
                tunnelsManager.addMultiple(tunnelConfigurations: configs.compactMap { $0 }) { numberSuccessful in
                    if numberSuccessful == configs.count {
                        completionHandler?()
                        return
                    }
                    let title = tr(format: "alertImportedFromZipTitle (%d)", numberSuccessful)
                    let message = tr(format: "alertImportedFromZipMessage (%1$d of %2$d)", numberSuccessful, configs.count)
                    errorPresenterType.showErrorAlert(title: title, message: message, from: sourceVC, onPresented: completionHandler)
                }
            }
        } else /* if (url.pathExtension == "conf") -- we assume everything else is a conf */ {
            let fileName = url.lastPathComponent
            let fileBaseName = url.deletingPathExtension().lastPathComponent.trimmingCharacters(in: .whitespacesAndNewlines)
            let fileContents: String
            do {
                fileContents = try String(contentsOf: url)
            } catch let error {
                let message: String
                if let cocoaError = error as? CocoaError, cocoaError.isFileError {
                    message = error.localizedDescription
                } else {
                    message = tr(format: "alertCantOpenInputConfFileMessage (%@)", fileName)
                }
                errorPresenterType.showErrorAlert(title: tr("alertCantOpenInputConfFileTitle"), message: message, from: sourceVC, onPresented: completionHandler)
                return
            }
            if let tunnelConfiguration = try? TunnelConfiguration(fromWgQuickConfig: fileContents, called: fileBaseName) {
                tunnelsManager.add(tunnelConfiguration: tunnelConfiguration) { result in
                    if let error = result.error {
                        errorPresenterType.showErrorAlert(error: error, from: sourceVC, onPresented: completionHandler)
                    } else {
                        completionHandler?()
                    }
                }
            } else {
                errorPresenterType.showErrorAlert(title: tr("alertBadConfigImportTitle"), message: tr(format: "alertBadConfigImportMessage (%@)", fileName),
                                              from: sourceVC, onPresented: completionHandler)
            }
        }
    }

}
