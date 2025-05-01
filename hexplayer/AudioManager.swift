// Created by Hex on May 1, 2025.

import Foundation
import AVFoundation
import SwiftUI
import AppKit

enum PlaybackMode {
    case sequential, loop, shuffle
}

class AudioManager: NSObject, ObservableObject, AVAudioPlayerDelegate {
    private static let notificationName = NSNotification.Name("AudioManagerTrackChanged")
    
    @Published var tracks: [Track] = []
    @Published var currentTrack: Track?
    @Published var isPlaying: Bool = false
    @Published var currentTime: TimeInterval = 0
    @Published var duration: TimeInterval = 0
    @Published var playbackMode: PlaybackMode = .sequential
    @Published var musicFolderURL: URL?
    
    var tracksLoaded: Bool = false
    
    private var player: AVAudioPlayer?
    private var playbackProgressTimer: Timer?
    private var playedIndices: [Int] = []
    private var previousIndices: [Int] = []
    private var isChangingTrack: Bool = false
    
    private var allowUIUpdates = false
    
    private static let playbackProgressNotification = NSNotification.Name("PlaybackProgressNotification")
    
    var audioPlayer: AVAudioPlayer? {
        return player
    }
    
    override init() {
        super.init()
        if let musicFolderPath = UserDefaults.standard.string(forKey: "musicFolderPath") {
            self.musicFolderURL = URL(fileURLWithPath: musicFolderPath)
            
            if let bookmarkData = UserDefaults.standard.data(forKey: "musicFolderBookmark") {
                do {
                    var isStale = false
                    let resolvedURL = try URL(resolvingBookmarkData: bookmarkData, 
                                             options: .withSecurityScope, 
                                             relativeTo: nil, 
                                             bookmarkDataIsStale: &isStale)
                    
                    if resolvedURL.startAccessingSecurityScopedResource() {
                        self.musicFolderURL = resolvedURL
                        
                        if isStale {
                            print("Bookmark was stale, updating...")
                            if let newBookmarkData = try? resolvedURL.bookmarkData(options: .withSecurityScope, 
                                                                              includingResourceValuesForKeys: nil, 
                                                                              relativeTo: nil) {
                                UserDefaults.standard.set(newBookmarkData, forKey: "musicFolderBookmark")
                            }
                        }
                        
                        loadMusicFiles()
                    } else {
                        print("Failed to start accessing security-scoped resource")
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                            self?.promptForMusicFolderReselection()
                        }
                    }
                } catch {
                    print("Failed to resolve bookmark: \(error)")
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                        self?.promptForMusicFolderReselection()
                    }
                }
            } else {
                loadMusicFiles()
            }
        }
        #if os(iOS) || os(tvOS)
        let audioSession = AVAudioSession.sharedInstance()
        do {
            try audioSession.setCategory(.playback)
            try audioSession.setActive(true)
        } catch {
            print("Failed to set audio session: \(error)")
        }
        #endif
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handlePlaybackProgress),
            name: AudioManager.playbackProgressNotification,
            object: nil
        )
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
        stopPlaybackProgressUpdates()
        
        if let _ = musicFolderURL, 
           let bookmarkData = UserDefaults.standard.data(forKey: "musicFolderBookmark") {
            do {
                var isStale = false
                let resolvedURL = try URL(resolvingBookmarkData: bookmarkData, 
                                         options: .withSecurityScope, 
                                         relativeTo: nil, 
                                         bookmarkDataIsStale: &isStale)
                resolvedURL.stopAccessingSecurityScopedResource()
            } catch {
                print("Error during cleanup: \(error)")
            }
        }
    }
    
    func showDesktopWarningIfNeeded(for url: URL) {
        let desktopPath = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first?.path ?? ""
        if url.path.hasPrefix(desktopPath) {
            DispatchQueue.main.async {
                let alert = NSAlert()
                alert.messageText = "⚠️ It is not recommended to put the music folder on the Desktop"
                alert.informativeText = "Due to macOS security mechanisms, it is recommended to put the music folder in Documents, Downloads, or Music directories to avoid permission issues."
                alert.alertStyle = .warning
                alert.addButton(withTitle: "OK")
                alert.runModal()
            }
        }
    }
    
    func chooseFolder(completion: @escaping (Bool) -> Void) {
        let openPanel = NSOpenPanel()
        openPanel.canChooseFiles = false
        openPanel.canChooseDirectories = true
        openPanel.allowsMultipleSelection = false
        openPanel.message = "Please select a folder containing audio files"
        openPanel.prompt = "Select"
        openPanel.begin { [weak self] (result) in
            guard let self = self else { 
                completion(false)
                return 
            }
            if result == .OK, let url = openPanel.url {
                self.showDesktopWarningIfNeeded(for: url)
                do {
                    if url.startAccessingSecurityScopedResource() {
                        let bookmarkData = try url.bookmarkData(options: .withSecurityScope, 
                                                              includingResourceValuesForKeys: nil, 
                                                              relativeTo: nil)
                        UserDefaults.standard.set(bookmarkData, forKey: "musicFolderBookmark")
                        self.musicFolderURL = url
                        UserDefaults.standard.set(url.path, forKey: "musicFolderPath")
                        self.tracksLoaded = false
                        self.loadMusicFiles()
                        completion(true)
                    } else {
                        print("Failed to access security-scoped resource")
                        let alert = NSAlert()
                        alert.messageText = "Permission Error"
                        alert.informativeText = "Could not access the selected folder. Please try a different location."
                        alert.alertStyle = .warning
                        alert.addButton(withTitle: "OK")
                        alert.runModal()
                        completion(false)
                    }
                } catch {
                    print("Failed to create folder bookmark: \(error)")
                    completion(false)
                }
            } else {
                completion(false)
            }
        }
    }
    
    func setMusicFolder(url: URL) {
        showDesktopWarningIfNeeded(for: url)
        
        if let _ = musicFolderURL, 
           let bookmarkData = UserDefaults.standard.data(forKey: "musicFolderBookmark") {
            do {
                var isStale = false
                let resolvedURL = try URL(resolvingBookmarkData: bookmarkData, 
                                         options: .withSecurityScope, 
                                         relativeTo: nil, 
                                         bookmarkDataIsStale: &isStale)
                resolvedURL.stopAccessingSecurityScopedResource()
            } catch {
                print("Error during cleanup: \(error)")
            }
        }
        
        if url.startAccessingSecurityScopedResource() {
            do {
                let bookmarkData = try url.bookmarkData(options: .withSecurityScope, 
                                                      includingResourceValuesForKeys: nil, 
                                                      relativeTo: nil)
                UserDefaults.standard.set(bookmarkData, forKey: "musicFolderBookmark")
                musicFolderURL = url
                UserDefaults.standard.set(url.path, forKey: "musicFolderPath")
                tracksLoaded = false
                loadMusicFiles()
            } catch {
                print("Failed to create bookmark: \(error)")
                url.stopAccessingSecurityScopedResource()
            }
        } else {
            print("Failed to access security-scoped resource for \(url.path)")
        }
    }
    
    func loadMusicFiles() {
        guard let folderURL = musicFolderURL else { return }
        
        var hasSecurityAccess = false
        if let bookmarkData = UserDefaults.standard.data(forKey: "musicFolderBookmark") {
            do {
                var isStale = false
                let resolvedURL = try URL(resolvingBookmarkData: bookmarkData, 
                                         options: .withSecurityScope, 
                                         relativeTo: nil, 
                                         bookmarkDataIsStale: &isStale)
                
                hasSecurityAccess = resolvedURL.startAccessingSecurityScopedResource()
                if hasSecurityAccess {
                    self.musicFolderURL = resolvedURL
                }
            } catch {
                print("Error resolving bookmark: \(error)")
            }
        }
        
        let loadQueue = DispatchQueue(label: "com.hexplayer.fileLoading", qos: .background)
        
        self.allowUIUpdates = true
        
        loadQueue.async { [weak self] in
            guard let self = self else { 
                if hasSecurityAccess {
                    folderURL.stopAccessingSecurityScopedResource()
                }
                return 
            }
            
            defer {
                if hasSecurityAccess {
                    DispatchQueue.main.async {
                        folderURL.stopAccessingSecurityScopedResource()
                    }
                }
            }
            
            autoreleasepool {
                let fileManager = FileManager.default
                if !fileManager.isReadableFile(atPath: folderURL.path) {
                    print("Error: Cannot access directory at \(folderURL.path). Check permissions.")
                    DispatchQueue.main.async {
                        self.tracksLoaded = true
                        
                        if folderURL.path.contains("/Desktop/") {
                            self.promptForMusicFolderReselection()
                        }
                    }
                    return
                }
                
                let contents: [URL]
                do {
                    contents = try fileManager.contentsOfDirectory(at: folderURL, includingPropertiesForKeys: nil)
                } catch {
                    print("Error listing directory contents: \(error.localizedDescription)")
                    DispatchQueue.main.async {
                        self.tracksLoaded = true
                        self.promptForMusicFolderReselection()
                    }
                    return
                }
                
                let maxFilesToProcess = 100
                let processedContents = contents.prefix(maxFilesToProcess)
                
                let supportedExtensions: Set<String> = ["mp3", "m4a"]
                var audioTracks: [Track] = []
                audioTracks.reserveCapacity(min(100, processedContents.count))
                
                for url in processedContents {
                    autoreleasepool {
                        let ext = url.pathExtension.lowercased()
                        if supportedExtensions.contains(ext) {
                            let fileSize: Int64 = (try? fileManager.attributesOfItem(atPath: url.path)[.size] as? Int64) ?? 0
                            let isLiked = UserDefaults.standard.bool(forKey: "liked_\(url.lastPathComponent)")
                            let track = Track(url: url, fileSize: fileSize, isLiked: isLiked)
                            track.playCount = UserDefaults.standard.integer(forKey: "playCount_\(url.lastPathComponent)")
                            audioTracks.append(track)
                            
                            if audioTracks.count % 5 == 0 {
                                Thread.sleep(forTimeInterval: 0.1)
                            }
                        }
                    }
                }
                
                print("Found \(audioTracks.count) audio files in \(folderURL.path)")
                
                DispatchQueue.main.async { [weak self] in
                    guard let self = self else { return }
                    self.tracks = audioTracks
                    self.tracksLoaded = true
                    
                    DispatchQueue.main.asyncAfter(deadline: .now() + 5.0) {
                        self.allowUIUpdates = false
                    }
                }
                
                DispatchQueue.main.async { [weak self] in
                    self?.objectWillChange.send()
                }
                
                DispatchQueue.main.async {
                    self.allowUIUpdates = false
                }
            }
        }
    }
    
    private func promptForMusicFolderReselection() {
        let alert = NSAlert()
        alert.messageText = "Music Folder Access Error"
        alert.informativeText = "Permission to access the music folder has expired. Would you like to select it again?"
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Select Folder")
        alert.addButton(withTitle: "Cancel")
        
        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            self.chooseFolder { _ in }
        }
    }
    
    func play() {
        guard let track = currentTrack else {
            if !tracks.isEmpty {
                currentTrack = tracks[0]
                play()
            }
            return
        }
        
        track.loadDurationIfNeeded()
        
        allowUIUpdates = true
        
        do {
            if let existingPlayer = player, !existingPlayer.isPlaying {
                existingPlayer.play()
                
                startPlaybackProgressUpdates()
                
                DispatchQueue.main.async { [weak self] in
                    guard let self = self else { return }
                    self.isPlaying = true
                }
                return
            }
            
            stopPlayer(updateUI: false)
            
            player = try AVAudioPlayer(contentsOf: track.url)
            player?.delegate = self
            player?.prepareToPlay()
            player?.volume = player?.volume ?? 1.0
            
            player?.play()
            
            startPlaybackProgressUpdates()
            
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                self.isPlaying = true
                self.duration = self.player?.duration ?? 0
                self.currentTime = 0
                
                DispatchQueue.global(qos: .background).async {
                    let trackId = track.id
                    let trackUrl = track.url
                    
                    DispatchQueue.main.async {
                        if let trackToUpdate = self.tracks.first(where: { $0.id == trackId }) {
                            trackToUpdate.playCount += 1
                        }
                        
                        UserDefaults.standard.set(track.playCount, forKey: "playCount_\(trackUrl.lastPathComponent)")
                    }
                    
                    if let index = self.tracks.firstIndex(where: { $0.id == trackId }),
                       !self.playedIndices.contains(index) {
                        self.playedIndices.append(index)
                    }
                }
            }
        } catch {
            print("Error playing track: \(error)")
            isPlaying = false
        }
    }
    
    private func startPlaybackProgressUpdates() {
        stopPlaybackProgressUpdates()
        
        playbackProgressTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self = self, let player = self.player, player.isPlaying else { return }
            
            let newTime = Double(Int(player.currentTime))
            if newTime != self.currentTime {
                NotificationCenter.default.post(
                    name: AudioManager.playbackProgressNotification,
                    object: nil,
                    userInfo: ["currentTime": newTime]
                )
            }
        }
    }
    
    private func stopPlaybackProgressUpdates() {
        playbackProgressTimer?.invalidate()
        playbackProgressTimer = nil
    }
    
    @objc private func handlePlaybackProgress(notification: Notification) {
        if let userInfo = notification.userInfo,
           let currentTime = userInfo["currentTime"] as? TimeInterval {
            if self.currentTime != currentTime {
                DispatchQueue.main.async { [weak self] in
                    guard let self = self, !self.isChangingTrack else { return }
                    self.currentTime = currentTime
                }
            }
        }
    }
    
    func pause() {
        player?.pause()
        stopPlaybackProgressUpdates()
        
        allowUIUpdates = true
        
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.isPlaying = false
        }
    }
    
    func stop() {
        stopPlayer()
        currentTrack = nil
    }
    
    func stopPlayer(updateUI: Bool = true) {
        if player != nil {
            player?.pause()
            player?.delegate = nil
            player = nil
        }
        
        stopPlaybackProgressUpdates()
        
        if updateUI {
            allowUIUpdates = true
            
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                self.isPlaying = false
                self.currentTime = 0
            }
        }
    }
    
    func playPause() {
        if isPlaying {
            pause()
        } else {
            play()
        }
    }
    
    func next() {
        if isChangingTrack {
            return
        }
        
        let nextIndex = calculateNextTrackIndex()
        guard nextIndex >= 0 else { return }
        
        isChangingTrack = true
        changeTrack(to: nextIndex)
    }
    
    private func calculateNextTrackIndex() -> Int {
        guard let currentTrack = currentTrack,
              let currentIndex = tracks.firstIndex(where: { $0.id == currentTrack.id }) else {
            return tracks.isEmpty ? -1 : 0
        }
        
        switch playbackMode {
        case .sequential:
            return (currentIndex + 1) % tracks.count
        case .loop:
            return currentIndex
        case .shuffle:
            if playedIndices.count >= tracks.count {
                playedIndices.removeAll()
                playedIndices.append(currentIndex)
            }
            var availableIndex: Int? = nil
            for i in 0..<tracks.count {
                if !playedIndices.contains(i) && i != currentIndex {
                    if Double.random(in: 0...1) < 0.2 || availableIndex == nil {
                        availableIndex = i
                    }
                }
            }
            return availableIndex ?? (currentIndex + 1) % tracks.count
        }
    }
    
    private func changeTrack(to index: Int) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.stopPlayer()
            self.currentTime = 0
            self.currentTrack = self.tracks[index]
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                guard let self = self else { return }
                self.play()
                self.isChangingTrack = false
                
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                    NotificationCenter.default.post(name: AudioManager.notificationName, object: nil)
                }
            }
        }
    }
    
    func previous() {
        if isChangingTrack {
            return
        }
        guard let currentTrack = currentTrack,
              let currentIndex = tracks.firstIndex(where: { $0.id == currentTrack.id }) else {
            if !tracks.isEmpty {
                self.currentTrack = tracks[0]
                play()
            }
            return
        }
        var previousIndex: Int
        switch playbackMode {
        case .sequential:
            previousIndex = (currentIndex - 1 + tracks.count) % tracks.count
        case .loop:
            previousIndex = currentIndex
        case .shuffle:
            if previousIndices.isEmpty {
                let availableIndices = Array(0..<tracks.count).filter { $0 != currentIndex }
                previousIndex = availableIndices.randomElement() ?? (currentIndex - 1 + tracks.count) % tracks.count
            } else {
                previousIndex = previousIndices.removeLast()
            }
        }
        isChangingTrack = true
        stopPlayer()
        self.currentTime = 0
        self.currentTrack = tracks[previousIndex]
        NotificationCenter.default.post(name: AudioManager.notificationName, object: nil)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            guard let self = self else { return }
            self.play()
            self.isChangingTrack = false
        }
    }
    
    func seek(to position: Double) {
        guard let player = player else { return }
        
        player.currentTime = position
        
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.currentTime = position
        }
    }
    
    func togglePlaybackMode() {
        switch playbackMode {
        case .sequential:
            playbackMode = .loop
        case .loop:
            playbackMode = .shuffle
            playedIndices.removeAll()
        case .shuffle:
            playbackMode = .sequential
        }
    }
    
    func toggleLiked(for track: Track) {
        let newLikedStatus = !track.isLiked
        track.isLiked = newLikedStatus
        
        UserDefaults.standard.set(newLikedStatus, forKey: "liked_\(track.url.lastPathComponent)")
        
        if tracks.contains(where: { $0.id == track.id }) {
            objectWillChange.send()
        }
    }
    
    func sortTracks(by criteria: SortCriteria) {
        switch criteria {
        case .fileName:
            tracks.sort { $0.name.lowercased() < $1.name.lowercased() }
        case .playCount:
            tracks.sort { $0.playCount > $1.playCount }
        case .liked:
            tracks.sort { track1, track2 in
                if track1.isLiked && !track2.isLiked {
                    return true
                } else if !track1.isLiked && track2.isLiked {
                    return false
                } else {
                    return track1.name.lowercased() < track2.name.lowercased()
                }
            }
        }
    }
    
    func setVolume(_ volume: Double) {
        player?.volume = Float(volume)
    }
    
    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        if isChangingTrack {
            return
        }
        
        isChangingTrack = true
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            guard let self = self else { return }
            
            self.allowUIUpdates = true
            
            if flag {
                if self.playbackMode == .loop {
                    self.stopPlayer(updateUI: false)
                    self.play()
                } else {
                    self.isChangingTrack = false
                    self.next()
                }
            } else {
                self.isChangingTrack = false
                self.isPlaying = false
            }
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 5.0) {
                self.allowUIUpdates = false
            }
        }
    }
    
    func selectTrack(_ track: Track) {
        guard !isChangingTrack else { return }
        
        isChangingTrack = true
        stopPlayer()
        currentTime = 0
        currentTrack = track
        
        if let index = tracks.firstIndex(where: { $0.id == track.id }),
           !playedIndices.contains(index) {
            playedIndices.append(index)
        }
        
        NotificationCenter.default.post(name: AudioManager.notificationName, object: nil)
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            guard let self = self else { return }
            self.play()
            self.isChangingTrack = false
        }
    }
    
    func exportLikedSongs() -> URL? {
        let likedTracks = tracks.filter { $0.isLiked }
        
        let likedData = likedTracks.map { $0.url.lastPathComponent }
        
        guard let jsonData = try? JSONSerialization.data(withJSONObject: likedData, options: .prettyPrinted) else {
            print("Failed to create JSON data")
            return nil
        }
        
        let tempDir = FileManager.default.temporaryDirectory
        let exportURL = tempDir.appendingPathComponent("HexPlayer_LikedSongs.json")
        
        do {
            try jsonData.write(to: exportURL)
            return exportURL
        } catch {
            print("Failed to write liked songs file: \(error)")
            return nil
        }
    }
    
    func importLikedSongs(from url: URL) -> (success: Int, failed: Int) {
        var successCount = 0
        var failedCount = 0
        
        do {
            let data = try Data(contentsOf: url)
            guard let paths = try JSONSerialization.jsonObject(with: data) as? [String] else {
                print("Failed to parse JSON data")
                return (0, 0)
            }
            
            let trackDict = Dictionary(grouping: tracks, by: { $0.url.lastPathComponent })
            
            for path in paths {
                if let matchedTracks = trackDict[path], let track = matchedTracks.first {
                    track.isLiked = true
                    UserDefaults.standard.set(true, forKey: "liked_\(path)")
                    successCount += 1
                } else {
                    failedCount += 1
                }
            }
            
            objectWillChange.send()
            
            return (successCount, failedCount)
        } catch {
            print("Error importing liked songs: \(error)")
            return (successCount, failedCount)
        }
    }
}
