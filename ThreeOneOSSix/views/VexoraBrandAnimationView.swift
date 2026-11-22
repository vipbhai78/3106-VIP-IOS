import SwiftUI
import AVFoundation
import UIKit

/// Branded, silent looping promo video displayed beneath the five quick-patch slots.
struct VexoraBrandAnimationView: View {
    @State private var player = AVQueuePlayer()
    @State private var looper: AVPlayerLooper?

    var body: some View {
        ZStack {
            LoopingVideoLayer(player: player)
                .background(Color.black)
                .clipShape(RoundedRectangle(cornerRadius: 24))
            RoundedRectangle(cornerRadius: 24)
                .stroke(Color.purple.opacity(0.78), lineWidth: 1.2)
                .allowsHitTesting(false)
        }
        .aspectRatio(900.0 / 420.0, contentMode: .fit)
        .shadow(color: .purple.opacity(0.2), radius: 18, y: 5)
        .onAppear {
            guard looper == nil,
                  let url = Bundle.main.url(forResource: "VexoraProLoop", withExtension: "mp4") else { return }
            let item = AVPlayerItem(url: url)
            looper = AVPlayerLooper(player: player, templateItem: item)
            player.isMuted = true
            player.play()
        }
        .onDisappear { player.pause() }
        .accessibilityLabel("Vexora Pro animated brand video")
    }
}

private struct LoopingVideoLayer: UIViewRepresentable {
    let player: AVPlayer

    func makeUIView(context: Context) -> PlayerContainerView {
        let view = PlayerContainerView()
        view.playerLayer.player = player
        view.playerLayer.videoGravity = .resizeAspectFill
        return view
    }

    func updateUIView(_ uiView: PlayerContainerView, context: Context) {
        uiView.playerLayer.player = player
    }
}

private final class PlayerContainerView: UIView {
    override class var layerClass: AnyClass { AVPlayerLayer.self }
    var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
}
