
import Foundation
import ARKit
import AVFoundation

enum ScanState: Equatable {
    case idle
    case scanning
    case finalizing
    case saved(mapId: UUID?)
    case error(message: String)
}

struct ScanQualityMetrics: Equatable {
    // Already present
    var worldMappingStatus: ARFrame.WorldMappingStatus = .notAvailable
    var featurePointCount: Int = 0
    var secondsElapsed: TimeInterval = 0

    // NEW: Grid coverage (your 2D map)
    var gridFilledCells: Int = 0        // cells marked free/occupied (not unknown)
    var gridTotalCells: Int = 0         // total cells in map grid
    var coveragePercent: Int {
        guard gridTotalCells > 0 else { return 0 }
        return min(100, Int((Double(gridFilledCells) / Double(gridTotalCells)) * 100.0))
    }

    // Tracking sub-score (0–100), same as you have (tweak weights if you’d like)
    var trackingScore: Int {
        var score = 0
        switch worldMappingStatus {
        case .mapped:    score += 60
        case .extending: score += 40
        case .limited:   score += 15
        default: break
        }
        // feature points lift (0–25)
        if featurePointCount >= 3000 { score += 25 }
        else { score += min(25, Int((Double(featurePointCount)/3000.0)*25.0)) }
        // time lift (0–15)
        if secondsElapsed >= 12 { score += 15 }
        else { score += Int((secondsElapsed/12.0)*15.0) }
        return min(100, score)
    }

    // NEW: Combine both into ONE bar users can trust
    // Weighting: 60% tracking + 40% coverage (tune to taste)
    var overallScore: Int {
        let s = 0.6 * Double(trackingScore) + 0.4 * Double(coveragePercent)
        return min(100, Int(s.rounded()))
    }

    // Gate "Finish & Save" on BOTH tracking and coverage
    var meetsSaveThreshold: Bool {
        // Tracking must be decent
        let okTracking = (worldMappingStatus == .mapped || worldMappingStatus == .extending)
                          && featurePointCount >= 2000
                          && secondsElapsed >= 8
        // Coverage must be non-trivial (e.g., 25%+)
        let okCoverage = coveragePercent >= 25
        return okTracking && okCoverage
    }
}


final class VoiceFeedback {
    static let shared = VoiceFeedback()
    private let synth = AVSpeechSynthesizer()
    func say(_ text: String) {
        let utter = AVSpeechUtterance(string: text)
        utter.voice = AVSpeechSynthesisVoice(language: Locale.current.identifier)
        utter.rate = AVSpeechUtteranceDefaultSpeechRate
        synth.speak(utter)
    }
}
