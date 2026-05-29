import AVFoundation
import SwiftUI

/// Silently loops an MP4 video file from the main bundle.
/// Falls back to clear (transparent) if the file isn't found.
struct LoopingVideoView: UIViewRepresentable {
    let filename: String

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> UIView {
        let view = PlayerView()
        guard let url = Bundle.main.url(forResource: filename, withExtension: "mp4") else {
            return view
        }
        let item = AVPlayerItem(url: url)
        let player = AVQueuePlayer(playerItem: item)
        player.isMuted = true
        player.preventsDisplaySleepDuringVideoPlayback = false
        context.coordinator.looper = AVPlayerLooper(player: player, templateItem: item)
        context.coordinator.player = player
        view.playerLayer.player = player
        view.playerLayer.videoGravity = .resizeAspectFill
        player.play()
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {}

    class Coordinator {
        var player: AVQueuePlayer?
        var looper: AVPlayerLooper?
    }
}

private final class PlayerView: UIView {
    override class var layerClass: AnyClass { AVPlayerLayer.self }
    var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
}
