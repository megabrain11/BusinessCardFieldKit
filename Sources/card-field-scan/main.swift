import AppleVisionAdapter
import CardFieldCore
import Foundation

#if canImport(CoreGraphics) && canImport(CoreImage) && canImport(ImageIO) && canImport(Vision)
  private struct Options {
    var recognitionLevel: AppleVisionScanConfiguration.RecognitionLevel = .accurate
    var languages = ["ko-KR", "en-US"]
    var isolatesCardRegion = true
    var enablesPreprocessing = true
    var enablesDualPass = true
    var enablesTargetedReRecognition = true
    var infersTokenLanguages = true
    var includesTokens = false
    var prettyPrinted = true
    var paths: [String] = []
  }

  private struct RegionOutput: Codable {
    var mode: String
    var boundingBox: NormalizedBoundingBox?
    var confidence: Double?
    var selectionScore: Double?

    init(_ selection: AppleVisionCardRegionSelection) {
      switch selection {
      case .disabled:
        mode = "disabled"
      case .fullImageFallback:
        mode = "fullImageFallback"
      case .isolated(let region):
        mode = "isolated"
        boundingBox = region.boundingBox
        confidence = region.confidence
        selectionScore = region.selectionScore
      }
    }
  }

  private struct ScanOutput: Codable {
    var source: String
    var status: String
    var cardRegion: RegionOutput?
    var fields: CardFieldResult?
    var tokens: [OCRToken]?
    var error: String?

    static func success(
      source: String,
      result: AppleVisionScanResult,
      includesTokens: Bool
    ) -> ScanOutput {
      ScanOutput(
        source: source,
        status: "ok",
        cardRegion: RegionOutput(result.cardRegionSelection),
        fields: result.fields,
        tokens: includesTokens ? result.tokens : nil,
        error: nil
      )
    }

    static func failure(source: String, error: any Error) -> ScanOutput {
      ScanOutput(
        source: source,
        status: "error",
        cardRegion: nil,
        fields: nil,
        tokens: nil,
        error: error.localizedDescription
      )
    }
  }

  private let usage = """
    Usage: card-field-scan [options] <image> [<image> ...]

    Options:
      --language <BCP-47>     Add an OCR language hint (repeatable).
      --fast                  Use fast rather than accurate text recognition.
      --no-card-isolation     OCR the complete image without foreground-card detection.
      --no-preprocess         Skip upscale, grayscale, and sharpening enhancement.
      --no-dual-pass          Recognize once instead of corrected plus uncorrected passes.
      --no-re-recognize       Skip upscaled re-recognition of low-confidence lines.
      --no-language-inference Leave token language unset instead of inferring from script.
      --include-tokens        Include raw OCR text and geometry in JSON output.
      --compact               Emit compact rather than pretty-printed JSON.
      -h, --help              Show this help.

    Images and results stay local. Output is written only to standard output.
    """

  private enum ArgumentError: LocalizedError {
    case missingLanguage
    case unknownOption(String)
    case missingImages

    var errorDescription: String? {
      switch self {
      case .missingLanguage:
        "--language requires a non-empty BCP 47 tag."
      case .unknownOption(let option):
        "Unknown option: \(option)"
      case .missingImages:
        "At least one image path is required."
      }
    }
  }

  private func parseOptions(_ arguments: [String]) throws -> Options? {
    var options = Options()
    var explicitLanguages: [String] = []
    var index = 0
    var acceptsOptions = true

    while index < arguments.count {
      let argument = arguments[index]
      if acceptsOptions, argument == "--" {
        acceptsOptions = false
      } else if acceptsOptions, argument == "--language" {
        index += 1
        guard index < arguments.count, !arguments[index].isEmpty else {
          throw ArgumentError.missingLanguage
        }
        explicitLanguages.append(arguments[index])
      } else if acceptsOptions, argument == "--fast" {
        options.recognitionLevel = .fast
      } else if acceptsOptions, argument == "--no-card-isolation" {
        options.isolatesCardRegion = false
      } else if acceptsOptions, argument == "--no-preprocess" {
        options.enablesPreprocessing = false
      } else if acceptsOptions, argument == "--no-dual-pass" {
        options.enablesDualPass = false
      } else if acceptsOptions, argument == "--no-re-recognize" {
        options.enablesTargetedReRecognition = false
      } else if acceptsOptions, argument == "--no-language-inference" {
        options.infersTokenLanguages = false
      } else if acceptsOptions, argument == "--include-tokens" {
        options.includesTokens = true
      } else if acceptsOptions, argument == "--compact" {
        options.prettyPrinted = false
      } else if acceptsOptions, argument == "--help" || argument == "-h" {
        return nil
      } else if acceptsOptions, argument.hasPrefix("-") {
        throw ArgumentError.unknownOption(argument)
      } else {
        options.paths.append(argument)
      }
      index += 1
    }

    guard !options.paths.isEmpty else { throw ArgumentError.missingImages }
    if !explicitLanguages.isEmpty { options.languages = explicitLanguages }
    return options
  }

  private func writeStandardError(_ message: String) {
    FileHandle.standardError.write(Data(message.utf8))
  }

  do {
    guard let options = try parseOptions(Array(CommandLine.arguments.dropFirst())) else {
      print(usage)
      exit(0)
    }

    let regionMode: AppleVisionCardRegionConfiguration.Mode =
      options.isolatesCardRegion ? .automatic : .disabled
    var preprocessing = AppleVisionPreprocessingConfiguration()
    preprocessing.isEnabled = options.enablesPreprocessing
    let scanner = AppleVisionScanner(
      configuration: AppleVisionScanConfiguration(
        recognitionLevel: options.recognitionLevel,
        recognitionLanguages: options.languages,
        automaticallyDetectsLanguage: true,
        usesLanguageCorrection: true,
        minimumTextHeight: 0.005,
        cardRegion: AppleVisionCardRegionConfiguration(mode: regionMode),
        preprocessing: preprocessing,
        dualPassRecognition: options.enablesDualPass,
        performsTargetedReRecognition: options.enablesTargetedReRecognition,
        infersTokenLanguages: options.infersTokenLanguages
      )
    )

    var failed = false
    let outputs = options.paths.map { path -> ScanOutput in
      let source = URL(fileURLWithPath: path).lastPathComponent
      do {
        let data = try Data(contentsOf: URL(fileURLWithPath: path))
        let result = try scanner.scan(imageData: data)
        return .success(source: source, result: result, includesTokens: options.includesTokens)
      } catch {
        failed = true
        return .failure(source: source, error: error)
      }
    }

    let encoder = JSONEncoder()
    encoder.outputFormatting =
      options.prettyPrinted ? [.prettyPrinted, .sortedKeys] : [.sortedKeys]
    FileHandle.standardOutput.write(try encoder.encode(outputs))
    FileHandle.standardOutput.write(Data("\n".utf8))
    if failed { exit(1) }
  } catch {
    writeStandardError("\(error.localizedDescription)\n\n\(usage)\n")
    exit(64)
  }
#else
  FileHandle.standardError.write(
    Data("card-field-scan requires Apple Vision, Core Image, and Core Graphics.\n".utf8)
  )
  exit(69)
#endif
