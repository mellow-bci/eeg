import Foundation
import CoreFoundation

extension EEGTrialEvidence {
    /// Shared live-write and replay revision invariant.
    func validateRevision(after previous: EEGTrialEvidence?) throws {
        guard let previous else {
            guard phase == .planned,events.isEmpty else { throw Failure.invalidTransition }
            return
        }
        // Report observations live outside Event.detail. Once reported they
        // must be retained by review/interruption revisions, not reinterpreted
        // from a later snapshot during recovery.
        if previous.participantReport != nil {
            guard participantReport == previous.participantReport,
                  observedBehavior == previous.observedBehavior else { throw Failure.invalidTransition }
        }
        let encoder=JSONEncoder();encoder.outputFormatting=[.sortedKeys]
        guard previous.phase != .reviewed,previous.phase != .interrupted,
              previous.id == id,previous.sessionID == sessionID,previous.participantID == participantID,
              previous.requestedCondition == requestedCondition,previous.startingNumber == startingNumber,
              events.count == previous.events.count+1,
              try encoder.encode(Array(events.dropLast())) == encoder.encode(previous.events) else { throw Failure.invalidTransition }
    }
    /// Recover by replaying allowed transitions, then compare every serialized
    /// field with the reconstructed state. An accepted flag alone is insufficient.
    public static func recover(_ data: Data) throws -> EEGTrialEvidence {
        guard data.count <= 4 * 1024 * 1024,
              let value = try JSONDecoder().decode(TrialJSONValue.self,from:data).foundationValue as? [String: Any],
              let id=value["id"] as? String,let session=value["sessionID"] as? String,
              let participant=value["participantID"] as? String,
              let raw=value["requestedCondition"] as? String,let condition=Condition(rawValue: raw),
              let number=value["startingNumber"] as? Int,
              let events=value["events"] as? [[String:Any]] else { throw Failure.invalidTransition }
        var result = try EEGTrialEvidence(id:id,sessionID:session,participantID:participant,condition:condition,startingNumber:number)
        for event in events {
            guard let kind=event["kind"] as? String,let at=event["at"] as? Double else { throw Failure.invalidTransition }
            switch kind {
            case "cue_requested": try result.requestCue(at:at,participantReady:true,audioCheckHeard:true,transportStable:true,recordingActive:true)
            case "cue_playback_started": try result.cueStarted(at:at)
            case "cue_playback_completed": try result.cueCompleted(at:at)
            case "end_cue_requested": try result.requestEndCue(at:at)
            case "end_cue_playback_started": try result.endCueStarted(at:at)
            case "end_cue_playback_completed": try result.endCueCompleted(at:at)
            case "participant_report":
                guard let raw=event["detail"] as? String,let report=ParticipantReport(rawValue:raw),
                      let behavior=value["observedBehavior"] as? String else { throw Failure.invalidReview }
                try result.report(report,at:at,observedBehavior:behavior)
            case "operator_review":
                guard let accept=value["accepted"] as? Bool,let reviewer=value["reviewer"] as? String,
                      let reason=event["detail"] as? String else { throw Failure.invalidReview }
                try result.review(accept:accept,reviewer:reviewer,reason:reason,at:at)
            case "interrupted":
                guard let reason=event["detail"] as? String else { throw Failure.invalidReview }
                try result.interrupt(reason:reason,at:at)
            default: throw Failure.invalidTransition
            }
        }
        let reconstructed = try JSONDecoder().decode(TrialJSONValue.self,from:JSONEncoder().encode(result)).foundationValue
        guard equalJSON(reconstructed,value) else {throw Failure.invalidTransition}
        return result
    }
    /// Compare JSON values, not NSNumber's reserialized decimal spelling. Numeric
    /// equality is exact in the Double representation used by event timestamps;
    /// booleans remain distinct from numeric 0/1 and unknown keys still reject.
    private static func equalJSON(_ lhs:Any,_ rhs:Any)->Bool {
        if let a=lhs as? [String:Any],let b=rhs as? [String:Any] {
            return Set(a.keys)==Set(b.keys) && a.allSatisfy {key,value in equalJSON(value,b[key]!)}
        }
        if let a=lhs as? [Any],let b=rhs as? [Any] {
            return a.count==b.count && zip(a,b).allSatisfy {equalJSON($0,$1)}
        }
        if let a=lhs as? NSNumber,let b=rhs as? NSNumber {
            let ab=CFGetTypeID(a)==CFBooleanGetTypeID(),bb=CFGetTypeID(b)==CFBooleanGetTypeID()
            guard ab==bb else {return false}
            return ab ? a.boolValue==b.boolValue : a.doubleValue.isFinite && b.doubleValue.isFinite && a.doubleValue==b.doubleValue
        }
        if let a=lhs as? String,let b=rhs as? String {return a==b}
        return lhs is NSNull && rhs is NSNull
    }

}

/// Decode numbers directly to the representation used by trial timestamps, avoiding
/// NSDecimalNumber conversion drift during repeated JSONSerialization passes.
private enum TrialJSONValue: Decodable {
    case object([String:TrialJSONValue]),array([TrialJSONValue]),string(String),number(Double),bool(Bool),null
    init(from decoder:Decoder) throws {
        let c=try decoder.singleValueContainer()
        if c.decodeNil() {self = .null}
        else if let v=try? c.decode(Bool.self) {self = .bool(v)}
        else if let v=try? c.decode(Double.self),v.isFinite {self = .number(v)}
        else if let v=try? c.decode(String.self) {self = .string(v)}
        else if let v=try? c.decode([TrialJSONValue].self) {self = .array(v)}
        else {self = .object(try c.decode([String:TrialJSONValue].self))}
    }
    var foundationValue:Any {
        switch self {
        case .object(let v):return v.mapValues(\.foundationValue)
        case .array(let v):return v.map(\.foundationValue)
        case .string(let v):return v
        case .number(let v):return NSNumber(value:v)
        case .bool(let v):return NSNumber(value:v)
        case .null:return NSNull()
        }
    }
}
