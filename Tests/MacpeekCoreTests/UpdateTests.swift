import Foundation
import Testing
@testable import MacpeekCore

@Suite struct UpdateTests {
    @Test func versionOrdering() {
        #expect(UpdateChecker.isNewer("v0.3.0", than: "0.2.5"))
        #expect(UpdateChecker.isNewer("0.2.10", than: "0.2.9"))
        #expect(!UpdateChecker.isNewer("0.2.5", than: "0.2.5"))
        #expect(!UpdateChecker.isNewer("garbage", than: "0.2.5"))
    }

    @Test func parsesRelease() throws {
        let release = """
        {"tag_name":"v0.2.0","html_url":"https://github.com/o/r/releases/tag/v0.2.0","assets":[
         {"name":"Macpeek.zip","browser_download_url":"https://example.com/Macpeek.zip"},
         {"name":"Macpeek.zip.sha256","browser_download_url":"https://example.com/Macpeek.zip.sha256"}]}
        """
        let info = try #require(UpdateChecker.parseLatestRelease(Data(release.utf8)))
        #expect(info.version == "0.2.0")
        #expect(info.checksumURL?.absoluteString == "https://example.com/Macpeek.zip.sha256")
    }

    @Test func checksumVerification() {
        let good = "2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824  Macpeek.zip\n"
        #expect(UpdateChecker.verifyChecksum(Data("hello".utf8), checksumFile: good))
        #expect(!UpdateChecker.verifyChecksum(Data("hellO".utf8), checksumFile: good))
    }
}
