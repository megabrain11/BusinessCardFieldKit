import CardFieldCore
import Foundation
import Testing

@testable import AppleVisionAdapter

#if canImport(CoreGraphics) && canImport(CoreImage) && canImport(ImageIO) && canImport(Vision)
  @Test("Golden scenes reproduce their expected fields through the complete pipeline")
  func goldenScenesReproduceExpectedFields() async throws {
    let scenes = try GoldenSceneManifest.load()
    #expect(scenes.count >= 5)

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
      let scene = scenes.first(where: { $0.identifier == "golden-korean-card" })
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

  @Test("Golden manifest stays unique, bounded, and fictional")
  func goldenManifestHygiene() throws {
    let scenes = try GoldenSceneManifest.load()

    #expect(Set(scenes.map(\.identifier)).count == scenes.count)
    #expect(scenes.allSatisfy { $0.identifier.hasPrefix("golden-") })

    let knownFields = Set(CardField.allCases.map(\.rawValue))
    for scene in scenes {
      #expect(scene.canvas.width >= 320)
      #expect(scene.canvas.height >= 200)
      #expect(!scene.lines.isEmpty)

      for line in scene.lines {
        #expect((0...1).contains(line.x))
        #expect((0...1).contains(line.y))
        #expect(line.fontSize >= 16)
        #expect((0...1).contains(scene.resolvedTextGray))
      }

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
