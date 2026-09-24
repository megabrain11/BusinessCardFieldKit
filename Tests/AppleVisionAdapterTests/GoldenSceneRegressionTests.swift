import AppleVisionBenchmarking
import CardFieldCore
import Foundation
import Testing

@testable import AppleVisionAdapter

#if canImport(CoreGraphics) && canImport(CoreImage) && canImport(ImageIO) && canImport(Vision)
  @Test("Golden scenes reproduce their expected fields through the complete pipeline")
  func goldenScenesReproduceExpectedFields() async throws {
    let scenes = try GoldenSceneManifest.load()
    #expect(scenes.count == 50)

    var failures: [String] = []
    for scene in scenes {
      let image = try GoldenSceneRenderer.render(scene)
      let scanner = AppleVisionScanner(configuration: scene.scanConfiguration)
      let scan = try await scanner.scanAsync(cgImage: image)

      let fieldMismatches = GoldenFieldComparator.mismatches(
        expected: scene.expected, result: scan.fields
      )
      failures.append(
        contentsOf: fieldMismatches.map { "\(scene.identifier): \($0)" })

      let regionMatches: Bool
      switch scan.cardRegionSelection {
      case .disabled:
        regionMatches = scene.resolvedCardRegionIsDisabled
      case .isolated, .fullImageFallback:
        regionMatches = !scene.resolvedCardRegionIsDisabled
      }
      if !regionMatches {
        failures.append(
          "\(scene.identifier): card region \(scan.cardRegionSelection) does not match configured mode"
        )
      }
    }

    if !failures.isEmpty {
      Issue.record("Golden scene regressions:\n\(failures.joined(separator: "\n"))")
    }
  }

  @Test("Repeated golden scans of the Hangul scene stay identical")
  func goldenSceneRepeatScansAreStable() async throws {
    let scenes = try GoldenSceneManifest.load()
    guard
      let scene = scenes.first(where: {
        $0.layoutIdentifier == "golden-korean-card" && $0.variantIdentifier == "clean"
      })
    else {
      Issue.record("golden-korean-card missing from manifest")
      return
    }

    let image = try GoldenSceneRenderer.render(scene)
    let scanner = AppleVisionScanner(configuration: scene.scanConfiguration)
    let first = try await scanner.scanAsync(cgImage: image)
    let second = try await scanner.scanAsync(cgImage: image)

    #expect(first.tokens.map(\.text) == second.tokens.map(\.text))
    #expect(first.fields == second.fields)
    #expect(first.cardRegionSelection == second.cardRegionSelection)
  }

  @Test("Golden scenes remain valid with column-aware classification enabled")
  func goldenScenesSupportColumnAwareClassification() async throws {
    let scenes = try GoldenSceneManifest.load()
    let classifier = CardFieldClassifier(
      columnAwareOptions: ColumnAwareClassifierOptions(mode: .enabled)
    )
    var failures: [String] = []
    for scene in scenes {
      let scanner = AppleVisionScanner(
        classifier: classifier,
        configuration: scene.scanConfiguration
      )
      let scan = try await scanner.scanAsync(cgImage: GoldenSceneRenderer.render(scene))
      failures.append(
        contentsOf: GoldenFieldComparator.mismatches(
          expected: scene.expected,
          result: scan.fields
        ).map { "\(scene.identifier): \($0)" }
      )
    }

    if !failures.isEmpty {
      Issue.record("Column-aware golden regressions:\n\(failures.joined(separator: "\n"))")
    }
  }

  @Test("Golden scenes remain valid with strict-field correction enabled")
  func goldenScenesSupportStrictFieldCorrection() async throws {
    let scenes = try GoldenSceneManifest.load()
    let classifier = CardFieldClassifier(
      strictFieldCorrectionOptions: StrictFieldCorrectionOptions(mode: .enabled)
    )
    var failures: [String] = []
    for scene in scenes {
      let scanner = AppleVisionScanner(
        classifier: classifier,
        configuration: scene.scanConfiguration
      )
      let scan = try await scanner.scanAsync(cgImage: GoldenSceneRenderer.render(scene))
      failures.append(
        contentsOf: GoldenFieldComparator.mismatches(
          expected: scene.expected,
          result: scan.fields
        ).map { "\(scene.identifier): \($0)" }
      )
    }

    if !failures.isEmpty {
      Issue.record("Strict-field golden regressions:\n\(failures.joined(separator: "\n"))")
    }
  }

  @Test("Conditional dual-pass remains field-identical across the golden corpus")
  func conditionalDualPassGoldenParity() async throws {
    let scenes = try GoldenSceneManifest.load()
    var failures: [String] = []
    var skipCount = 0
    for scene in scenes {
      let image = try GoldenSceneRenderer.render(scene)
      var baselineConfiguration = scene.scanConfiguration
      baselineConfiguration.diagnostics = AppleVisionDiagnosticsOptions(isEnabled: true)
      var experimentalConfiguration = baselineConfiguration
      experimentalConfiguration.conditionalDualPass = AppleVisionConditionalDualPassOptions(
        mode: .enabled)

      let baseline = try await AppleVisionScanner(configuration: baselineConfiguration)
        .scanAsync(cgImage: image)
      let experimental = try await AppleVisionScanner(configuration: experimentalConfiguration)
        .scanAsync(cgImage: image)
      if baseline.fields != experimental.fields {
        failures.append("\(scene.identifier): fields changed")
      }
      if baseline.cardRegionSelection != experimental.cardRegionSelection {
        failures.append("\(scene.identifier): card-region selection changed")
      }
      skipCount += experimental.diagnostics?.dualPassSkipCount ?? 0
    }

    if !failures.isEmpty {
      Issue.record("Conditional dual-pass golden regressions:\n\(failures.joined(separator: "\n"))")
    }
    #expect(skipCount > 0)
  }

  @Test("Golden manifest stays unique, bounded, and fictional")
  func goldenManifestHygiene() throws {
    let scenes = try GoldenSceneManifest.load()

    #expect(Set(scenes.map(\.identifier)).count == scenes.count)
    #expect(scenes.allSatisfy { $0.identifier.hasPrefix("golden-") })

    let knownFields = Set(CardField.allCases.map(\.rawValue))
    for scene in scenes {
      #expect(scene.canvas.width >= 320)
      #expect(scene.canvas.height >= 200)
      #expect(!scene.profile.lines.isEmpty)
      #expect(scene.profile.lines.count == 5)
      #expect((0...1).contains(scene.textGray))

      if let quad = scene.cardQuad {
        #expect(quad.count == 4)
        #expect(quad.allSatisfy { $0.count == 2 })
        #expect(quad.allSatisfy { point in point.allSatisfy { (0...1).contains($0) } })
      }

      #expect(Set(scene.expected.keys).isSubset(of: knownFields))

      let emails = scene.expected[CardField.emailAddresses.rawValue] ?? []
      let websites = scene.expected[CardField.websites.rawValue] ?? []
      let profiles = scene.expected[CardField.professionalProfileURLs.rawValue] ?? []
      let phones =
        (scene.expected[CardField.workPhoneNumbers.rawValue] ?? [])
        + (scene.expected[CardField.mobilePhoneNumbers.rawValue] ?? [])
        + (scene.expected[CardField.faxNumbers.rawValue] ?? [])

      #expect(
        emails.allSatisfy { $0.contains("example.") || $0.hasSuffix(".example") })
      #expect(websites.allSatisfy { $0.contains("example") })
      #expect(profiles.allSatisfy { $0.contains("example") })
      #expect(
        phones.allSatisfy {
          let digitsOnly = GoldenFieldComparator.digits($0)
          return digitsOnly.contains("555") || digitsOnly.hasPrefix("010")
        }
      )
    }
  }
#else
  @Test("Golden scene tests require Apple Vision")
  func goldenSceneTestsUnavailable() {}
#endif
