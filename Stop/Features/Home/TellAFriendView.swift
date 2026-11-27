import CoreImage
import CoreImage.CIFilterBuiltins
import SwiftUI

/// Makes QR codes on the device with Core Image (no network).
enum QRCodeGenerator {
    /// A black-on-white QR code for `string` (error correction M), scaled up by a whole number of pixels per
    /// module with nearest-neighbour sampling so the edges stay sharp. At least `minimumPixelSize` wide.
    /// Core Image's output has no quiet zone to speak of; the view adds one with white padding.
    static func image(for string: String, minimumPixelSize: Int = 1024) -> CGImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(string.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage, output.extent.width > 0 else { return nil }
        let scale = (CGFloat(minimumPixelSize) / output.extent.width).rounded(.up)
        let scaled = output.samplingNearest().transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        return CIContext(options: [.useSoftwareRenderer: false]).createCGImage(scaled, from: scaled.extent)
    }
}

/// "Tell a friend": a QR code for the App Store page that friends scan with their camera, and a share link.
/// Opened from Settings.
struct TellAFriendView: View {
    private let qrCode = QRCodeGenerator.image(for: AppInfo.appStoreURL.absoluteString)

    var body: some View {
        ScrollView {
            VStack(spacing: Theme.Spacing.l) {
                StopSign(size: 64)
                    .padding(.top, Theme.Spacing.m)

                VStack(spacing: Theme.Spacing.s) {
                    Text("Scan to get Stop",
                         comment: "Tell a friend screen title, above a QR code that opens the app's App Store page.")
                        .font(Theme.Typography.title)
                        .multilineTextAlignment(.center)
                        .accessibilityAddTraits(.isHeader)
                    Text("Friends can point their iPhone camera at this code to open \(AppInfo.name) on the App Store.",
                         comment: "Tell a friend screen subtitle. The argument is the app's name.")
                        .font(Theme.Typography.body)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }

                if let qrCode {
                    // Always black on white (in dark mode too), on a white card that is also the quiet zone.
                    Image(decorative: qrCode, scale: 1)
                        .interpolation(.none)
                        .resizable()
                        .scaledToFit()
                        .padding(Theme.Spacing.l)
                        .background(.white, in: .rect(cornerRadius: Theme.Radius.card))
                        .frame(maxWidth: 320)
                        .shadow(color: .black.opacity(0.12), radius: 12, y: 4)
                        .accessibilityElement()
                        .accessibilityLabel(Text("QR code for the App Store page",
                                                 comment: "VoiceOver label of the Tell a friend QR code."))
                        .accessibilityAddTraits(.isImage)
                        .accessibilityIdentifier("tellAFriendQRCode")
                }

                ShareLink(item: AppInfo.appStoreURL) {
                    Label {
                        Text("Share link", comment: "Tell a friend button that shares the App Store link.")
                    } icon: {
                        Image(systemName: "square.and.arrow.up")
                    }
                    .font(Theme.Typography.headline)
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .frame(maxWidth: 320)
                .accessibilityIdentifier("tellAFriendShareLink")
            }
            .padding(.horizontal, Theme.Spacing.l)
            .padding(.bottom, Theme.Spacing.l)
            .frame(maxWidth: .infinity)
        }
        .navigationTitle(Text("Tell a friend", comment: "Settings row and screen title: shows a QR code and a share link so friends can get the app."))
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview {
    NavigationStack { TellAFriendView() }
}
