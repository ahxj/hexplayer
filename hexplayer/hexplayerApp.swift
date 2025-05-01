// Created by Hex on May 1, 2025.

import SwiftUI
import AppKit
import MediaPlayer
import AVFoundation

class AppState {
    static let shared = AppState()
    let audioManager = AudioManager()
    
    private init() {}
}

class AppDelegate: NSObject, NSApplicationDelegate, ObservableObject {
    private var nowPlayingInfoCenterObserver: Any?
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        let audioManager = AppState.shared.audioManager
        
        if !NSApp.windows.contains(where: { $0.identifier?.rawValue == "HexPlayerMainWindow" }) {
            let contentView = ContentView()
                .environmentObject(audioManager)
            
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 320, height: 500),
                styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                backing: .buffered,
                defer: false
            )
            
            window.backgroundColor = NSColor.black
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.isOpaque = false
            window.hasShadow = true
            
            window.identifier = NSUserInterfaceItemIdentifier("HexPlayerMainWindow")
            window.isRestorable = true
            window.restorationClass = HexPlayerWindowRestoration.self
            
            window.contentView = NSHostingView(rootView: contentView)
            window.center()
            window.makeKeyAndOrderFront(nil)
        }
        
        setupMediaKeyHandling(for: audioManager)
        setupNowPlayingObservers(for: audioManager)
    }
    
    func applicationWillTerminate(_ notification: Notification) {
        if let observer = nowPlayingInfoCenterObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }
    
    func application(_ application: NSApplication, willEncodeRestorableState coder: NSCoder) {
    }
    
    func application(_ application: NSApplication, didDecodeRestorableState coder: NSCoder) {
    }
    
    private func setupMediaKeyHandling(for audioManager: AudioManager) {
        let commandCenter = MPRemoteCommandCenter.shared()
        
        commandCenter.playCommand.removeTarget(nil)
        commandCenter.pauseCommand.removeTarget(nil)
        commandCenter.togglePlayPauseCommand.removeTarget(nil)
        commandCenter.previousTrackCommand.removeTarget(nil)
        commandCenter.nextTrackCommand.removeTarget(nil)
        
        commandCenter.playCommand.addTarget { _ in
            if !audioManager.isPlaying {
                audioManager.playPause()
                self.updateNowPlayingInfo(for: audioManager)
                return .success
            }
            return .commandFailed
        }
        
        commandCenter.pauseCommand.addTarget { _ in
            if audioManager.isPlaying {
                audioManager.playPause()
                self.updateNowPlayingInfo(for: audioManager)
                return .success
            }
            return .commandFailed
        }
        
        commandCenter.togglePlayPauseCommand.addTarget { _ in
            audioManager.playPause()
            self.updateNowPlayingInfo(for: audioManager)
            return .success
        }
        
        commandCenter.previousTrackCommand.addTarget { _ in
            audioManager.previous()
            self.updateNowPlayingInfo(for: audioManager)
            return .success
        }
        
        commandCenter.nextTrackCommand.addTarget { _ in
            audioManager.next()
            self.updateNowPlayingInfo(for: audioManager)
            return .success
        }
        
        NSApp.setActivationPolicy(.regular)
        
        updateNowPlayingInfo(for: audioManager)
        
        NSApp.activate(ignoringOtherApps: true)
    }
    
    private func updateNowPlayingInfo(for audioManager: AudioManager) {
        var nowPlayingInfo = [String: Any]()
        
        nowPlayingInfo[MPMediaItemPropertyTitle] = audioManager.currentTrack?.name ?? "Hex Player"
        nowPlayingInfo[MPMediaItemPropertyArtist] = "Hex Player"
        
        nowPlayingInfo[MPNowPlayingInfoPropertyElapsedPlaybackTime] = audioManager.currentTime
        nowPlayingInfo[MPMediaItemPropertyPlaybackDuration] = audioManager.duration
        nowPlayingInfo[MPNowPlayingInfoPropertyPlaybackRate] = audioManager.isPlaying ? 1.0 : 0.0
        
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nowPlayingInfo
    }
    
    private func setupNowPlayingObservers(for audioManager: AudioManager) {
        nowPlayingInfoCenterObserver = NotificationCenter.default.addObserver(
            forName: NSNotification.Name("AudioManagerTrackChanged"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.updateNowPlayingInfo(for: audioManager)
        }
        
        Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { [weak self] _ in
            if audioManager.isPlaying {
                self?.updateNowPlayingInfo(for: audioManager)
            }
        }
    }
}

final class HexPlayerWindowRestoration: NSObject, NSWindowRestoration {
    static func restoreWindow(withIdentifier identifier: NSUserInterfaceItemIdentifier, 
                              state: NSCoder, 
                              completionHandler: @escaping (NSWindow?, Error?) -> Void) {
        
        if identifier.rawValue == "HexPlayerMainWindow" {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 320, height: 500),
                styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                backing: .buffered,
                defer: false
            )
            
            window.backgroundColor = NSColor.black
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.isOpaque = false
            window.hasShadow = true
            window.identifier = identifier
            
            let contentView = ContentView()
                .environmentObject(AppState.shared.audioManager)
            
            window.contentView = NSHostingView(rootView: contentView)
            
            completionHandler(window, nil)
        } else {
            completionHandler(nil, nil)
        }
    }
}

@main
struct hexplayerApp: App {
    @ObservedObject private var audioManager = AppState.shared.audioManager
    
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    var body: some Scene {
        Settings {
            EmptyView()
        }
        .commands {
            CommandGroup(replacing: .appSettings) {
                Button("Open Music Folder") {
                    let panel = NSOpenPanel()
                    panel.canChooseDirectories = true
                    panel.canChooseFiles = false
                    panel.allowsMultipleSelection = false
                    
                    if panel.runModal() == .OK {
                        if let url = panel.url {
                            audioManager.setMusicFolder(url: url)
                        }
                    }
                }
                .keyboardShortcut("O", modifiers: .command)
                
                Divider()
                
                Button("Reset") {
                    if let domain = Bundle.main.bundleIdentifier {
                        UserDefaults.standard.removePersistentDomain(forName: domain)
                        UserDefaults.standard.synchronize()
                        let alert = NSAlert()
                        alert.messageText = "Reset Successful"
                        alert.informativeText = "All preferences and stored data have been cleared."
                        alert.addButton(withTitle: "OK")
                        alert.runModal()
                    }
                }
                .keyboardShortcut("R", modifiers: .command)

                Divider()
                
                Button("Export Liked Songs") {
                    let audioManager = AppState.shared.audioManager
                    if let exportURL = audioManager.exportLikedSongs() {
                        let savePanel = NSSavePanel()
                        savePanel.nameFieldStringValue = "HexPlayer_LikedSongs.json"
                        savePanel.allowedContentTypes = [UTType(filenameExtension: "json")!]
                        savePanel.canCreateDirectories = true
                        savePanel.message = "Save your liked songs list"
                        savePanel.prompt = "Save"
                        
                        savePanel.begin { (result) in
                            if result == .OK, let url = savePanel.url {
                                do {
                                    let data = try Data(contentsOf: exportURL)
                                    try data.write(to: url)
                                    
                                    let alert = NSAlert()
                                    alert.messageText = "Export Successful"
                                    alert.informativeText = "Your liked songs have been exported successfully."
                                    alert.addButton(withTitle: "OK")
                                    alert.runModal()
                                } catch {
                                    let alert = NSAlert()
                                    alert.messageText = "Export Failed"
                                    alert.informativeText = "Failed to export liked songs: \(error.localizedDescription)"
                                    alert.addButton(withTitle: "OK")
                                    alert.runModal()
                                }
                            }
                        }
                    } else {
                        let alert = NSAlert()
                        alert.messageText = "Export Failed"
                        alert.informativeText = "Failed to prepare liked songs data for export."
                        alert.addButton(withTitle: "OK")
                        alert.runModal()
                    }
                }
                .keyboardShortcut("E", modifiers: .command)
                
                Button("Import Liked Songs") {
                    let openPanel = NSOpenPanel()
                    openPanel.canChooseFiles = true
                    openPanel.canChooseDirectories = false
                    openPanel.allowsMultipleSelection = false
                    openPanel.allowedContentTypes = [UTType(filenameExtension: "json")!]
                    openPanel.message = "Select a liked songs file to import"
                    openPanel.prompt = "Import"
                    
                    openPanel.begin { (result) in
                        if result == .OK, let url = openPanel.url {
                            let audioManager = AppState.shared.audioManager
                            let result = audioManager.importLikedSongs(from: url)
                            
                            let alert = NSAlert()
                            alert.messageText = "Import Complete"
                            alert.informativeText = "Successfully imported \(result.success) liked songs. \(result.failed) songs could not be matched."
                            alert.addButton(withTitle: "OK")
                            alert.runModal()
                        }
                    }
                }
                .keyboardShortcut("I", modifiers: .command)
                
                Divider()

                Button("Project Homepage") {
                    if let url = URL(string: "https://github.com/ahxj/hexplayer") {
                        NSWorkspace.shared.open(url)
                    }
                }
                .keyboardShortcut("G", modifiers: .command)

                Button("Download Latest Release") {
                    if let url = URL(string: "https://github.com/ahxj/hexplayer/releases/latest") {
                        NSWorkspace.shared.open(url)
                    }
                }
                .keyboardShortcut("D", modifiers: .command)
            }
        }
    }
}
