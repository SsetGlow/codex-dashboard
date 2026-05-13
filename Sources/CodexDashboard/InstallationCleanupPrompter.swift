import AppKit
import Foundation

enum InstallationCleanupPrompter {
    private static let promptKey = "installationCleanupPrompted.0.1.2"
    private static let volumePath = "/Volumes/codex-dashboard"

    static func promptIfNeeded() {
        guard Bundle.main.bundleURL.path == "/Applications/codex-dashboard.app",
              UserDefaults.standard.bool(forKey: promptKey) == false,
              let mountedImage = findMountedInstallerImage() else {
            return
        }

        UserDefaults.standard.set(true, forKey: promptKey)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            let alert = NSAlert()
            alert.messageText = "Remove installer DMG?"
            alert.informativeText = "codex-dashboard is installed in Applications. You can eject the installer volume and move the downloaded DMG to Trash."
            alert.addButton(withTitle: "Move to Trash")
            alert.addButton(withTitle: "Keep")
            alert.alertStyle = .informational

            if alert.runModal() == .alertFirstButtonReturn {
                moveInstallerToTrash(mountedImage)
            }
        }
    }

    private static func findMountedInstallerImage() -> URL? {
        guard FileManager.default.fileExists(atPath: volumePath),
              let data = run("/usr/bin/hdiutil", arguments: ["info", "-plist"]),
              let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil),
              let root = plist as? [String: Any],
              let images = root["images"] as? [[String: Any]] else {
            return nil
        }

        for image in images {
            guard let imagePath = image["image-path"] as? String,
                  imagePath.hasSuffix(".dmg"),
                  let entities = image["system-entities"] as? [[String: Any]] else {
                continue
            }

            let isInstallerVolume = entities.contains { entity in
                entity["mount-point"] as? String == volumePath
            }
            if isInstallerVolume {
                return URL(fileURLWithPath: imagePath)
            }
        }

        return nil
    }

    private static func moveInstallerToTrash(_ imageURL: URL) {
        NSWorkspace.shared.recycle([imageURL]) { _, _ in
            _ = run("/usr/bin/hdiutil", arguments: ["detach", volumePath])
        }
    }

    private static func run(_ executable: String, arguments: [String]) -> Data? {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardOutput = pipe
        process.standardError = Pipe()

        do {
            try process.run()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else { return nil }
            return pipe.fileHandleForReading.readDataToEndOfFile()
        } catch {
            return nil
        }
    }
}
