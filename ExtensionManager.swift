import Foundation
import SystemExtensions
import os.log
internal import Combine

class ExtensionManager: NSObject, ObservableObject {
    @Published var statusMessage: String = "Unknown"
    
    let extensionBundleIdentifier = "com.protoarc.t1plus.driver" // This needs to match the actual bundle ID of the extension
    
    private let log = OSLog(subsystem: "com.protoarc.t1plus.app", category: "ExtensionManager")

    func installExtension() {
        statusMessage = "Installing extension..."
        let request = OSSystemExtensionRequest.activationRequest(forExtensionWithIdentifier: extensionBundleIdentifier, queue: .main)
        request.delegate = self
        OSSystemExtensionManager.shared.submitRequest(request)
        os_log("Submitted activation request for %{public}@", log: log, extensionBundleIdentifier)
    }
}

extension ExtensionManager: OSSystemExtensionRequestDelegate {
    func request(_ request: OSSystemExtensionRequest, actionForReplacingExtension existing: OSSystemExtensionProperties, withExtension ext: OSSystemExtensionProperties) -> OSSystemExtensionRequest.ReplacementAction {
        os_log("Replacing existing extension version %{public}@ with %{public}@", log: log, existing.bundleVersion, ext.bundleVersion)
        return .replace
    }
    
    func requestNeedsUserApproval(_ request: OSSystemExtensionRequest) {
        os_log("Extension requires user approval", log: log)
        statusMessage = "Needs User Approval. Please open System Settings > Privacy & Security to allow the extension."
    }
    
    func request(_ request: OSSystemExtensionRequest, didFinishWithResult result: OSSystemExtensionRequest.Result) {
        os_log("Request finished with result: %d", log: log, result.rawValue)
        statusMessage = result == .completed ? "Extension successfully installed/activated." : "Extension activation finished but not completed (will activate after reboot if required)."
    }
    
    func request(_ request: OSSystemExtensionRequest, didFailWithError error: Error) {
        os_log("Request failed with error: %{public}@", log: log, error.localizedDescription)
        statusMessage = "Failed: \(error.localizedDescription)"
    }
}
