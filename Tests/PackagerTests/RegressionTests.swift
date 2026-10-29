import XCTest
@testable import Packager

final class RegressionTests: XCTestCase {
    private var root: URL!
    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("PackagerTests-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws { try FileManager.default.removeItem(at: root) }

    func testMixedArchitectureIsNotLegacyOnly() {
        XCTAssertTrue(MachO.is32Bit(["i386", "x86_64"]))
        XCTAssertFalse(MachO.isLegacyOnly(["i386", "x86_64"]))
        XCTAssertFalse(MachO.isLegacyOnly(["arm64"]))
        XCTAssertFalse(MachO.isLegacyOnly([]))
        XCTAssertTrue(MachO.isLegacyOnly(["i386", "ppc"]))
    }

    func testFatMachOReadsAllSlices() throws {
        var bytes = [UInt8](repeating: 0, count: 512)
        func write(_ n: UInt32, at offset: Int) {
            bytes[offset] = UInt8(truncatingIfNeeded: n >> 24)
            bytes[offset + 1] = UInt8(truncatingIfNeeded: n >> 16)
            bytes[offset + 2] = UInt8(truncatingIfNeeded: n >> 8)
            bytes[offset + 3] = UInt8(truncatingIfNeeded: n)
        }
        write(0xCAFEBABE, at: 0); write(2, at: 4); write(7, at: 8); write(0x01000007, at: 28)
        let url = root.appendingPathComponent("fat")
        try Data(bytes).write(to: url)
        XCTAssertEqual(MachO.architectures(at: url), ["i386", "x86_64"])
    }

    func testJavaScriptVersionGateIsRemovedWithoutRunningCode() throws {
        let url = root.appendingPathComponent("Distribution")
        let xml = #"""
        <installer-gui-script><script><![CDATA[
        function checkOS() {
          var version = system.version.ProductVersion;
          if (system.compareVersions(version, '10.8') > 0) { my.result.message = 'Old OS required { }'; return false; }
          return true;
        }
        function selected() { return system.files.plistAtPath('/saved'); }
        ]]></script><installation-check script="checkOS()"/><choice start_selected="selected()"/></installer-gui-script>
        """#
        try xml.write(to: url, atomically: true, encoding: .utf8)
        XCTAssertEqual(try PackageRebuilder.sanitizeDistribution(at: url, log: { _ in }), 1)
        let doc = try XMLDocument(contentsOf: url)
        XCTAssertEqual(try doc.nodes(forXPath: "//installation-check").count, 0)
        XCTAssertEqual(try doc.nodes(forXPath: "//choice/@start_selected").first?.stringValue, "selected()")
        XCTAssertTrue((try String(contentsOf: url)).contains("plistAtPath"))
    }

    func testMixedHardwareAndVersionGateIsPreserved() throws {
        let url = root.appendingPathComponent("Distribution")
        try #"<installer-gui-script><script>function check() { return system.compareVersions(system.version.ProductVersion, '10.8') &gt; 0 &amp;&amp; system.sysctl('hw.memsize') &gt; 100; }</script><installation-check script="check()"/></installer-gui-script>"#.write(to: url, atomically: true, encoding: .utf8)
        XCTAssertEqual(VersionGates.gates(in: try XMLDocument(contentsOf: url)).count, 1)
        XCTAssertFalse(VersionGates.gates(in: try XMLDocument(contentsOf: url))[0].removable)
        XCTAssertEqual(try PackageRebuilder.sanitizeDistribution(at: url, log: { _ in }), 0)
        XCTAssertEqual(try XMLDocument(contentsOf: url).nodes(forXPath: "//installation-check").count, 1)
    }

    func testDirectJavaScriptGateAndXMLMaximumAreRemoved() throws {
        let url = root.appendingPathComponent("Distribution")
        try #"<installer-gui-script max-os-version="10.8"><installation-check script="system.compareVersions(system.version.ProductVersion, '10.8') &lt; 0"/><allowed-os-versions><os-version min="10.5" max="10.8"/></allowed-os-versions></installer-gui-script>"#.write(to: url, atomically: true, encoding: .utf8)
        XCTAssertEqual(try PackageRebuilder.sanitizeDistribution(at: url, log: { _ in }), 3)
        XCTAssertEqual(try XMLDocument(contentsOf: url).nodes(forXPath: "//installation-check | //allowed-os-versions | //@max-os-version").count, 0)
    }

    func testScriptPayloadSizeRepairPreservesScriptAndOtherMetadata() throws {
        let payload = root.appendingPathComponent("test.pkg/Scripts/payload")
        try FileManager.default.createDirectory(at: payload, withIntermediateDirectories: true)
        try Data(repeating: 1, count: 2050).write(to: payload.appendingPathComponent("file"))
        let script = payload.deletingLastPathComponent().appendingPathComponent("postinstall")
        try "do not run me".write(to: script, atomically: true, encoding: .utf8)
        try #"<installer-gui-script><pkg-ref id="test" installKBytes="0" version="1">#test.pkg</pkg-ref><pkg-ref id="empty" installKBytes="0">#empty.pkg</pkg-ref></installer-gui-script>"#.write(to: root.appendingPathComponent("Distribution"), atomically: true, encoding: .utf8)
        XCTAssertEqual(InstallSizeMetadata.issues(in: root).count, 1)
        XCTAssertEqual(try InstallSizeMetadata.repair(in: root, log: { _ in }), 1)
        XCTAssertEqual(InstallSizeMetadata.issues(in: root).count, 0)
        let doc = try XMLDocument(contentsOf: root.appendingPathComponent("Distribution"))
        XCTAssertEqual(try doc.nodes(forXPath: "//pkg-ref[@id='test']/@installKBytes").first?.stringValue, "3")
        XCTAssertEqual(try doc.nodes(forXPath: "//pkg-ref[@id='empty']/@installKBytes").first?.stringValue, "0")
        XCTAssertEqual(try String(contentsOf: script), "do not run me")
    }

    func testOutputNeverOverwritesAnExistingPackage() throws {
        try Data().write(to: root.appendingPathComponent("name.pkg"))
        XCTAssertEqual(PackageRebuilder.uniqueDestination(in: root, name: "name.pkg").lastPathComponent, "name 2.pkg")
        XCTAssertEqual(PackageRebuilder.normalizedOutputName("../name", fallbackSource: root), "..-name.pkg")
    }

    func testCLIVersionUsesTheBundledResource() {
        XCTAssertEqual(AppVersion.current, "1.1.0")
    }

    func testHostCompatibilitySeparatesNativeTranslationAndLegacy() {
        let arm = HostCapabilities(architecture: "arm64", macOS: "27.0.1", rosetta: true)
        let armWithoutRosetta = HostCapabilities(architecture: "arm64", macOS: "27.0.1", rosetta: false)
        let intel = HostCapabilities(architecture: "x86_64", macOS: "14.0", rosetta: false)
        XCTAssertEqual(CompatibilityAnalyzer.runtime(architectures: ["i386", "x86_64"], host: intel), .native)
        XCTAssertEqual(CompatibilityAnalyzer.runtime(architectures: ["x86_64"], host: arm), .translated)
        XCTAssertEqual(CompatibilityAnalyzer.runtime(architectures: ["x86_64"], host: armWithoutRosetta), .needsRosetta)
        XCTAssertEqual(CompatibilityAnalyzer.runtime(architectures: ["arm64", "x86_64"], host: arm), .native)
        XCTAssertEqual(CompatibilityAnalyzer.runtime(architectures: ["arm64"], host: intel), .incompatible)
        XCTAssertEqual(CompatibilityAnalyzer.runtime(architectures: ["i386"], host: arm), .incompatible)
        XCTAssertEqual(CompatibilityAnalyzer.runtime(architectures: ["unknown-0x42"], host: arm), .unknown)
        XCTAssertEqual(CompatibilityAnalyzer.summarize([.native, .incompatible], complete: true), .partial)
        XCTAssertEqual(CompatibilityAnalyzer.summarize([.native], complete: false), .unknown)
        XCTAssertEqual(CompatibilityAnalyzer.summarize([], complete: true), .unknown)
    }

    func testRosettaIsNotAssumedForGeneralAppsAfterMacOS27() {
        let future = HostCapabilities(architecture: "arm64", macOS: "28.0", rosetta: true)
        XCTAssertEqual(CompatibilityAnalyzer.runtime(architectures: ["x86_64"], host: future), .incompatible)
    }

    func testArchitectureDescriptionsExposeFamilyAndBitWidth() {
        XCTAssertEqual(CompatibilityAnalyzer.architecture("i386")["bits"] as? Int, 32)
        XCTAssertEqual(CompatibilityAnalyzer.architecture("x86_64")["family"] as? String, "Intel")
        XCTAssertEqual(CompatibilityAnalyzer.architecture("arm64")["bits"] as? Int, 64)
        XCTAssertEqual(CompatibilityAnalyzer.architecture("ppc64")["family"] as? String, "PowerPC")
    }
}
