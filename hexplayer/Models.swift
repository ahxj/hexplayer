// Created by Hex on May 1, 2025.

import Foundation
import AVFoundation

enum SortCriteria {
    case fileName, playCount, liked
}

class Track: Identifiable, ObservableObject, Equatable {
    let id = UUID()
    let url: URL
    let name: String
    let fileSize: Int64
    @Published var playCount: Int
    @Published var duration: TimeInterval = 0
    @Published var isTimeLoaded: Bool = false
    @Published var isLiked: Bool = false
    
    init(url: URL, playCount: Int = 0, fileSize: Int64 = 0, isLiked: Bool = false) {
        self.url = url
        self.name = url.deletingPathExtension().lastPathComponent
        self.playCount = playCount
        self.fileSize = fileSize
        self.isLiked = isLiked
    }
    
    static func == (lhs: Track, rhs: Track) -> Bool {
        return lhs.id == rhs.id
    }
    
    func loadDurationIfNeeded() {
        if isTimeLoaded || duration > 0 {
            return
        }
        
        DispatchQueue.main.async {
            self.isTimeLoaded = true
        }
        
        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let self = self else { return }
            
            do {
                if let audioPlayer = try? AVAudioPlayer(contentsOf: self.url) {
                    let durationValue = audioPlayer.duration
                    DispatchQueue.main.async {
                        self.duration = durationValue
                    }
                }
            }
        }
    }
    
    var formattedDuration: String {
        if duration > 0 {
            let minutes = Int(duration) / 60
            let seconds = Int(duration) % 60
            return String(format: "%02d:%02d", minutes, seconds)
        } else {
            return "--:--"
        }
    }
    
    var formattedFileSize: String {
        let byteCountFormatter = ByteCountFormatter()
        byteCountFormatter.allowedUnits = [.useMB]
        byteCountFormatter.countStyle = .file
        return byteCountFormatter.string(fromByteCount: fileSize)
    }
}