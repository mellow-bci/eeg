import EEGCore

extension EEGWindowInferenceResult {
    var interpretationLabel: String {
        switch interpretation {
        case .experimentalCandidate: return "Experimental candidate: " + (candidate ?? "")
        case .neutral: return "Neutral prediction"
        case .rejected: return "Rejected — no prediction"
        }
    }
}
