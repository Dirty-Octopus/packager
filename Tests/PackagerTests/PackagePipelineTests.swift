import XCTest
@testable import Packager

final class PackagePipelineTests: XCTestCase {
    private var root: URL!
    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("PackagerPipeline-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws { try FileManager.default.removeItem(at: root) }

    private func product(mixed: Bool) throws -> URL {
        let flatComponent = root.appendingPathComponent("component.pkg")
        let build = Shell.run("/usr/bin/pkgbuild", ["--nopayload", "--identifier", "test.packager.pipeline", "--version", "1", flatComponent.path])
        XCTAssertTrue(build.succeeded, build.combined)
        let expanded = root.appendingPathComponent("product")
        try FileManager.default.createDirectory(at: expanded, withIntermediateDirectories: true)
        let expand = Shell.run("/usr/sbin/pkgutil", ["--expand", flatComponent.path, expanded.appendingPathComponent("component.pkg").path])
        XCTAssertTrue(expand.succeeded, expand.combined)
        let predicate = mixed ? "return system.compareVersions(system.version.ProductVersion, '10.8') &gt; 0 &amp;&amp; system.sysctl('hw.memsize') &gt; 1;" : "return system.compareVersions(system.version.ProductVersion, '10.8') &lt; 0;"
        try """
        <installer-gui-script minSpecVersion="2" max-os-version="10.8"><title>Pipeline</title>
        <script>function checkOS() { \(predicate) }</script><installation-check script="checkOS()"/>
        <choices-outline><line choice="main"/></choices-outline><choice id="main"><pkg-ref id="test.packager.pipeline"/></choice>
        <pkg-ref id="test.packager.pipeline" version="1">#component.pkg</pkg-ref></installer-gui-script>
        """.write(to: expanded.appendingPathComponent("Distribution"), atomically: true, encoding: .utf8)
        let source = root.appendingPathComponent("input.pkg")
        let flatten = Shell.run("/usr/sbin/pkgutil", ["--flatten", expanded.path, source.path])
        XCTAssertTrue(flatten.succeeded, flatten.combined)
        return source
    }

    func testJavaScriptOnlyGateIsDetectedAndRepairedThroughThePipeline() throws {
        let source = try product(mixed: false)
        let inspection = try PackageInspector.inspect(source: source, workRoot: root.appendingPathComponent("workspace"), log: { _ in })
        XCTAssertEqual(inspection.stats.osConstraints, 2)
        XCTAssertEqual(inspection.distribution?.javaScriptGateCount, 1)
        var options = RebuildOptions.defaults(for: inspection)
        options.outputDirectory = root.appendingPathComponent("output")
        let result = try PackageRebuilder.rebuild(source: source, inspection: inspection, options: options, log: { _ in })
        XCTAssertTrue(result.verified)
        XCTAssertTrue(result.warnings.isEmpty)
        let again = try PackageInspector.inspect(source: result.outputURL, workRoot: root.appendingPathComponent("again"), log: { _ in })
        XCTAssertEqual(again.stats.osConstraints, 0)
    }

    func testMixedGateProducesAReviewWarningAfterRebuild() throws {
        let source = try product(mixed: true)
        let inspection = try PackageInspector.inspect(source: source, workRoot: root.appendingPathComponent("workspace"), log: { _ in })
        var options = RebuildOptions.defaults(for: inspection)
        options.outputDirectory = root.appendingPathComponent("output")
        let result = try PackageRebuilder.rebuild(source: source, inspection: inspection, options: options, log: { _ in })
        XCTAssertTrue(result.verified)
        XCTAssertEqual(result.warnings.count, 1)
        let again = try PackageInspector.inspect(source: result.outputURL, workRoot: root.appendingPathComponent("again"), log: { _ in })
        XCTAssertEqual(again.distribution?.javaScriptGateCount, 1)
    }
}
