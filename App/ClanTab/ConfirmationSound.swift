import AudioToolbox
import Foundation

/// The portfolio confirmation sound (`DESIGN_BIBLE.md` §5) — one short chime,
/// played *alongside* the success haptic (never instead of it) on the single
/// most significant confirming action. For ClanTab that's settling up.
///
/// `AudioServicesPlaySystemSound` routes through the ring/silent switch, so a
/// muted phone gets the haptic and nothing else — which is the point of pairing
/// the two rather than relying on either alone.
enum ConfirmationSound {
    private static let soundID: SystemSoundID = {
        var id: SystemSoundID = 0
        if let url = Bundle.main.url(forResource: "settled", withExtension: "caf") {
            AudioServicesCreateSystemSoundID(url as CFURL, &id)
        }
        return id
    }()

    /// Play the confirmation chime. No-op if the asset failed to load.
    static func play() {
        guard soundID != 0 else { return }
        AudioServicesPlaySystemSound(soundID)
    }
}
