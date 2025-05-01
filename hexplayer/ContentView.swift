// Created by Hex on May 1, 2025.

import SwiftUI
import AVFoundation
import Foundation

struct ContentView: View {
    @EnvironmentObject private var audioManager: AudioManager
    @State private var sortCriteria: SortCriteria = .fileName
    @State private var isShuffling = false
    @State private var isRepeatingSingle = false
    @State private var isPlaylistVisible = false
    @State private var playlistHeightOffset: CGFloat = 0
    
    @State private var keyboardMonitor: Any?
    
    private let playerWidth: CGFloat = 320
    private let playerHeight: CGFloat = 160
    private let playlistHeight: CGFloat = 330
    
    private var windowHeight: CGFloat {
        return isPlaylistVisible ? playerHeight + playlistHeight + playlistHeightOffset : playerHeight
    }
    
    private var actualPlaylistHeight: CGFloat {
        return playlistHeight + playlistHeightOffset
    }
    
    private let minPlaylistHeight: CGFloat = 330
    private let maxPlaylistHeight: CGFloat = 600
    
    var body: some View {
        ZStack {
            Color.black
            
            VStack(spacing: 0) {
                playerInterface
                    .frame(height: playerHeight)
                
                VStack(spacing: 0) {
    
                    PlaylistHeaderView(
                        sortCriteria: $sortCriteria,
                        audioManager: audioManager
                    )
                    
                    PlaylistView(
                        audioManager: audioManager
                    )
                }
                .frame(height: isPlaylistVisible ? actualPlaylistHeight : 0, alignment: .top)
                .clipped()
                .opacity(isPlaylistVisible ? 1 : 0)
            }
        }
        .frame(width: playerWidth, height: windowHeight)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .animation(.easeInOut(duration: 0.3), value: windowHeight)
        .animation(.easeInOut(duration: 0.3), value: isPlaylistVisible)
        .onChange(of: audioManager.tracksLoaded) { tracksLoaded in
            if tracksLoaded && !audioManager.tracks.isEmpty {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        isPlaylistVisible = true
                    }
                }
            }
        }
        .onAppear {
            setupKeyboardShortcuts()
        }
        .onDisappear {
            if let monitor = keyboardMonitor {
                NSEvent.removeMonitor(monitor)
                keyboardMonitor = nil
            }
        }
    }
    
    private func setupKeyboardShortcuts() {
        keyboardMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            switch event.keyCode {
            case 49:
                audioManager.playPause()
                return nil
            case 123:
                audioManager.previous()
                return nil
            case 124:
                audioManager.next()
                return nil
            default:
                break
            }
            return event
        }
    }
    
    private var playerInterface: some View {
        VStack(spacing: 10) {
            VStack(spacing: 4) {
                if let track = audioManager.currentTrack {
                    Text(track.name)
                        .font(.headline)
                        .foregroundColor(.white)
                        .lineLimit(1)
                        .padding(.horizontal)
                } else {
                    Text("Hex Player")
                        .font(.headline)
                        .foregroundColor(.white)
                        .padding(.horizontal)
                }
            }
            .padding(.top, 15)
            
            HStack(spacing: 25) {
                Button(action: {
                    audioManager.previous()
                }) {
                    Image(systemName: "backward.end.fill")
                        .font(.system(size: 25))
                        .foregroundColor(.white)
                }
                .buttonStyle(.plain)
                
                Button(action: {
                    audioManager.playPause()
                }) {
                    Image(systemName: audioManager.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 25))
                        .foregroundColor(.white)
                        .frame(width: 30)
                }
                .buttonStyle(.plain)
                
                Button(action: {
                    audioManager.next()
                }) {
                    Image(systemName: "forward.end.fill")
                        .font(.system(size: 25))
                        .foregroundColor(.white)
                }
                .buttonStyle(.plain)
            }
            .padding(.vertical, 8)
            
            ProgressBarView(audioManager: audioManager)
                .padding(.horizontal)
            
            HStack(spacing: 25) {
                Button(action: {
                    isShuffling.toggle()
                    audioManager.playbackMode = isShuffling ? .shuffle : .sequential
                }) {
                    Image(systemName: "shuffle")
                        .font(.system(size: 16))
                        .foregroundColor(isShuffling ? .blue : .gray)
                }
                .buttonStyle(.plain)
                
                Button(action: {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        isPlaylistVisible.toggle()
                    }
                }) {
                    Image(systemName: isPlaylistVisible ? "music.note.list" : "text.justify")
                        .font(.system(size: 18))
                        .foregroundColor(isPlaylistVisible ? .blue : .gray)
                }
                .buttonStyle(.plain)
                
                Button(action: {
                    isRepeatingSingle.toggle()
                    audioManager.playbackMode = isRepeatingSingle ? .loop : .sequential
                }) {
                    Image(systemName: isRepeatingSingle ? "repeat.1" : "repeat")
                        .font(.system(size: 16))
                        .foregroundColor(isRepeatingSingle ? .blue : .gray)
                }
                .buttonStyle(.plain)
            }
            .padding(.bottom, 8)
            
            Spacer()
        }
        .frame(width: playerWidth)
        .background(Color.black)
    }
}

struct ProgressBarView: View {
    @ObservedObject var audioManager: AudioManager
    @State private var isDragging = false
    @State private var localPosition: CGFloat = 0
    @State private var lastUpdateTime: TimeInterval = 0
    @State private var viewWidth: CGFloat = 180
    
    @State private var displayCurrentTime: TimeInterval = 0
    @State private var displayRemainingTime: TimeInterval = 0
    
    private let progressNotification = NotificationCenter.default
        .publisher(for: NSNotification.Name("PlaybackProgressNotification"))
    
    private let sliderHeight: CGFloat = 20
    private let updateThrottleInterval: TimeInterval = 5.0
    
    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Rectangle()
                    .fill(Color.gray.opacity(0.3))
                    .frame(height: 4)
                    .cornerRadius(2)
                
                Rectangle()
                    .fill(
                        LinearGradient(
                            gradient: Gradient(colors: [.blue.opacity(0.8), .blue]),
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: isDragging ? localPosition : calculateProgressWidth(totalWidth: geometry.size.width), height: 4)
                    .cornerRadius(2)
            }
            .frame(height: sliderHeight)
            .contentShape(Rectangle())
            .onAppear {
                self.viewWidth = geometry.size.width
                updateLocalPosition()
                updateDisplayTimes()
            }
            .onChange(of: geometry.size.width) { newWidth in
                self.viewWidth = newWidth
                updateLocalPosition()
            }
            .onReceive(progressNotification) { _ in
                let now = Date().timeIntervalSince1970
                if now - lastUpdateTime >= updateThrottleInterval && !isDragging {
                    lastUpdateTime = now
                    updateLocalPosition()
                    updateDisplayTimes()
                }
            }
            .onChange(of: audioManager.currentTime) { _ in
                let now = Date().timeIntervalSince1970
                if now - lastUpdateTime >= updateThrottleInterval && !isDragging {
                    lastUpdateTime = now
                    updateLocalPosition()
                    updateDisplayTimes()
                }
            }
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        isDragging = true
                        localPosition = min(max(0, value.location.x), viewWidth)
                        updateDisplayTimes()
                    }
                    .onEnded { value in
                        let finalPosition = min(max(0, value.location.x), viewWidth)
                        localPosition = finalPosition
                        updateDisplayTimes()
                        
                        let progress = finalPosition / viewWidth
                        let targetSeconds = Int(audioManager.duration * Double(progress))
                        
                        audioManager.seek(to: Double(targetSeconds))
                        
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                            isDragging = false
                            lastUpdateTime = Date().timeIntervalSince1970
                        }
                    }
            )
        }
    }
    
    private func updateDisplayTimes() {
        if isDragging {
            let time = getTimeFromPosition()
            displayCurrentTime = time
            displayRemainingTime = audioManager.duration - time
        } else {
            displayCurrentTime = audioManager.currentTime
            displayRemainingTime = audioManager.duration - audioManager.currentTime
        }
    }
    
    private func calculateProgressWidth(totalWidth: CGFloat) -> CGFloat {
        if audioManager.duration <= 0 { return 0 }
        let progress = min(audioManager.currentTime / audioManager.duration, 1.0)
        return CGFloat(progress) * totalWidth
    }
    
    private func getTimeFromPosition() -> TimeInterval {
        let progress = localPosition / viewWidth
        return Double(Int(audioManager.duration * Double(progress)))
    }
    
    private func updateLocalPosition() {
        localPosition = calculateProgressWidth(totalWidth: viewWidth)
    }
    
    private func formatTime(_ time: TimeInterval) -> String {
        let minutes = Int(time) / 60
        let seconds = Int(time) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}

struct PlaylistHeaderView: View {
    @Binding var sortCriteria: SortCriteria
    @ObservedObject var audioManager: AudioManager
    
    var body: some View {
        HStack {
            HStack(spacing: 8) {                
                Text("PLAYLIST")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(.gray)
            }
            .padding(.leading)
            
            Spacer()
            
            HStack(spacing: 16) {
    
                Button(action: {
                    withAnimation(.spring()) {
                        sortCriteria = .fileName
                        audioManager.sortTracks(by: sortCriteria)
                    }
                }) {
                    Text("Name")
                        .font(.caption)
                        .foregroundColor(sortCriteria == .fileName ? .blue : .gray)
                }
                .buttonStyle(.plain)

                Button(action: {
                    withAnimation(.spring()) {
                        sortCriteria = .liked
                        audioManager.sortTracks(by: sortCriteria)
                    }
                }) {
                    Text("Liked")
                        .font(.caption)
                        .foregroundColor(sortCriteria == .liked ? .blue : .gray)
                }
                .buttonStyle(.plain)
                
                Button(action: {
                    withAnimation(.spring()) {
                        sortCriteria = .playCount
                        audioManager.sortTracks(by: sortCriteria)
                    }
                }) {
                    Text("Plays")
                        .font(.caption)
                        .foregroundColor(sortCriteria == .playCount ? .blue : .gray)
                }
                .buttonStyle(.plain)
            }
            .padding(.trailing)
        }
        .padding(.vertical, 8)
        .background(Color.black.opacity(0.7))
    }
}

struct PlaylistView: View {
    @ObservedObject var audioManager: AudioManager
    @State private var scrollOffset: CGFloat = 0
    @State private var contentHeight: CGFloat = 0
    @State private var viewportHeight: CGFloat = 0
    
    var body: some View {
        GeometryReader { geometry in
            playlistContent(geometry: geometry)
        }
        .background(Color.black)
    }
    
    private func playlistContent(geometry: GeometryProxy) -> some View {
        ZStack(alignment: .trailing) {
            playlistScrollView
            
            if shouldShowScrollbar {
                scrollbarView
                    .padding(.vertical, 10)
                    .padding(.trailing, 2)
            }
        }
        .onAppear {
            viewportHeight = geometry.size.height
        }
        .onChange(of: geometry.size.height) { newHeight in
            viewportHeight = newHeight
        }
    }
    
    private var playlistScrollView: some View {
        ScrollView(showsIndicators: false) {
            scrollViewContent
        }
        .coordinateSpace(name: "scrollView")
        .onPreferenceChange(ScrollOffsetPreferenceKey.self) { offset in
            scrollOffset = -offset
        }
        .onPreferenceChange(ContentSizePreferenceKey.self) { height in
            contentHeight = height
        }
    }
    
    private var scrollViewContent: some View {
        ZStack(alignment: .top) {
            GeometryReader { geo in
                Color.clear.preference(
                    key: ScrollOffsetPreferenceKey.self,
                    value: geo.frame(in: .named("scrollView")).minY
                )
            }
            
            trackListContent
        }
    }
    
    private var trackListContent: some View {
        LazyVStack(spacing: 0) {
            ForEach(audioManager.tracks) { track in
                trackRow(for: track)
                
                Divider()
                    .background(Color.gray.opacity(0.2))
            }
        }
        .padding(.vertical, 4)
        .background(
            GeometryReader { geo in
                Color.clear.preference(
                    key: ContentSizePreferenceKey.self,
                    value: geo.size.height
                )
            }
        )
    }
    
    private func trackRow(for track: Track) -> some View {
        let isCurrentTrack = audioManager.currentTrack?.id == track.id
        
        return TrackRow(track: track, isPlaying: isCurrentTrack)
            .background(
                isCurrentTrack ? Color.blue.opacity(0.15) : Color.clear
            )
            .contentShape(Rectangle())
            .onTapGesture(count: 2) {
                withAnimation {
                    audioManager.selectTrack(track)
                }
            }
            .environmentObject(audioManager)
    }
    
    private var scrollbarView: some View {
        CustomScrollbar(
            contentHeight: contentHeight,
            viewportHeight: viewportHeight,
            scrollOffset: scrollOffset
        )
    }
    
    private var shouldShowScrollbar: Bool {
        return contentHeight > viewportHeight && !audioManager.tracks.isEmpty
    }
}

struct CustomScrollbar: View {
    let contentHeight: CGFloat
    let viewportHeight: CGFloat
    let scrollOffset: CGFloat
    
    private var thumbHeight: CGFloat {
        let ratio = min(viewportHeight / contentHeight, 1.0)
        return max(viewportHeight * ratio, 30)
    }
    
    private var thumbOffset: CGFloat {
        if contentHeight <= viewportHeight { return 0 }
        let availableScroll = contentHeight - viewportHeight
        let maxOffset = viewportHeight - thumbHeight
        let ratio = min(scrollOffset / availableScroll, 1.0)
        return ratio * maxOffset
    }
    
    var body: some View {
        ZStack(alignment: .top) {
            Rectangle()
                .fill(Color.white.opacity(0.05))
                .frame(width: 3)
                .cornerRadius(1.5)
            
            Rectangle()
                .fill(Color.blue.opacity(0.6))
                .frame(width: 3, height: thumbHeight)
                .cornerRadius(1.5)
                .offset(y: thumbOffset)
                .animation(.easeOut(duration: 0.2), value: scrollOffset)
        }
    }
}

struct ScrollOffsetPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

struct ContentSizePreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

struct TrackRow: View {
    @ObservedObject var track: Track
    let isPlaying: Bool
    @State private var isHovered = false
    @EnvironmentObject var audioManager: AudioManager
    
    var body: some View {
        HStack(spacing: 12) {
            if isPlaying {
                Image(systemName: "music.note")
                    .font(.caption)
                    .foregroundColor(.blue)
                    .frame(width: 16)
            } else {
                Color.clear
                    .frame(width: 16)
            }
            
            Button(action: {
                audioManager.toggleLiked(for: track)
            }) {
                Image(systemName: track.isLiked ? "heart.fill" : "heart")
                    .font(.caption)
                    .foregroundColor(track.isLiked ? .red : (isHovered ? .gray : .gray.opacity(0.5)))
            }
            .buttonStyle(.plain)
            .frame(width: 16)
            
            Text(track.name)
                .lineLimit(1)
                .truncationMode(.middle)
                .font(.system(size: 13))
                .foregroundColor(isPlaying ? .white : (isHovered ? .white : .gray))
            
            Spacer()
            
            Text(track.duration > 0 ? track.formattedDuration : "--:--")
                .font(.system(size: 12, design: .monospaced))
                .foregroundColor(.gray)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .contentShape(Rectangle())
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.2)) {
                isHovered = hovering
            }
        }
        .onAppear {
            if isPlaying {
                track.loadDurationIfNeeded()
            }
        }
    }
}

struct SettingsView: View {
    @Environment(\.presentationMode) var presentationMode
    @EnvironmentObject var audioManager: AudioManager
    
    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            HStack {
                Text("Settings")
                    .font(.title2)
                    .fontWeight(.semibold)
                    .foregroundColor(.white)
                
                Spacer()
                
                Button(action: {
                    presentationMode.wrappedValue.dismiss()
                }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title3)
                        .foregroundColor(.gray)
                }
                .buttonStyle(.plain)
            }
            
            VStack(alignment: .leading, spacing: 10) {
                Text("Music Folder")
                    .font(.headline)
                    .foregroundColor(.white)
                
                HStack {
                    if let path = audioManager.musicFolderURL?.path {
                        Text(path)
                            .font(.system(size: 13))
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .foregroundColor(.gray)
                            .padding(.trailing, 8)
                    } else {
                        Text("No folder selected")
                            .font(.system(size: 13))
                            .foregroundColor(.gray)
                            .padding(.trailing, 8)
                    }
                    
                    Spacer()
                    
                    Button("Choose") {
                        audioManager.chooseFolder { success in
                            if success {
                                print("Successfully selected and obtained folder permission")
                            } else {
                                print("Folder selection was cancelled or failed")
                            }
                        }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .tint(.blue)
                }
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color(white: 0.12))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                )
            }
            
            Spacer()
            
            HStack {
                Spacer()
                Button("Done") {
                    presentationMode.wrappedValue.dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .tint(.blue)
            }
        }
        .padding()
        .frame(minWidth: 400, minHeight: 300)
        .background(Color.black)
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
            .environmentObject(AudioManager())
            .preferredColorScheme(.dark)
    }
}
