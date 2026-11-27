import Foundation
import os
import StopSession

/// Where the app keeps its `FileGameStore`: Application Support/Stop.
enum StoreLocation {
    static var directory: URL {
        URL.applicationSupportDirectory.appending(path: "Stop", directoryHint: .isDirectory)
    }

    /// Opens the store, first deleting everything in it when `wipe` (`-uiTesting`, `-resetState`).
    static func makeStore(wipe: Bool, directory: URL = directory) -> FileGameStore {
        if wipe, FileManager.default.fileExists(atPath: directory.path) {
            do { try FileManager.default.removeItem(at: directory) } catch {
                Logger.app.error("wiping the store failed: \(error.localizedDescription, privacy: .public)")
            }
        }
        return FileGameStore(directory: directory)
    }
}
