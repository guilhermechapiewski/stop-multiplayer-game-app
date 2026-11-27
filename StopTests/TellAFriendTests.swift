import Foundation
import Testing
@testable import Stop

struct TellAFriendTests {
    @Test func appStoreURLIsTheAppsPage() {
        #expect(AppInfo.appStoreURL.absoluteString == "https://apps.apple.com/app/id6840139205")
    }

    @Test func qrCodeIsLargeAndSquare() throws {
        let image = try #require(QRCodeGenerator.image(for: AppInfo.appStoreURL.absoluteString))
        // At least 300 pt wide on a 3x screen, so it's crisp at any size the screen shows it.
        #expect(image.width >= 300 * 3)
        #expect(image.width == image.height)
    }

    @Test func qrCodeIsWholePixelsPerModule() throws {
        let image = try #require(QRCodeGenerator.image(for: AppInfo.appStoreURL.absoluteString, minimumPixelSize: 10))
        let large = try #require(QRCodeGenerator.image(for: AppInfo.appStoreURL.absoluteString))
        // Nearest-neighbour scaling by a whole factor: the big code is an exact multiple of the smallest one.
        #expect(large.width % image.width == 0)
    }
}
