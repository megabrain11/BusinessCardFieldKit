import AppleVisionAdapter
import CardFieldCore
import Vision

/// Example only: the host owns image capture, Vision request execution, review, and persistence.
func classifyFrontObservations(
    _ observations: [VNRecognizedTextObservation]
) throws -> CardFieldResult {
    let tokens = AppleVisionAdapter.tokens(from: observations)
    return try CardFieldClassifier().classify(tokens)
}
