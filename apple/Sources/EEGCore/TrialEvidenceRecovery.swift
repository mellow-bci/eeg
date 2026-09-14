import Foundation

extension EEGTrialEvidence {
    /// Shared live-write and replay revision invariant.
    func validateRevision(after previous: EEGTrialEvidence?) throws {
        guard let previous else {
            guard phase == .planned,events.isEmpty else { throw Failure.invalidTransition }
            return
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
              let value = try JSONSerialization.jsonObject(with: data) as? [String: Any],
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
        let reconstructed = try JSONSerialization.jsonObject(with: JSONEncoder().encode(result))
        guard try JSONSerialization.data(withJSONObject:reconstructed,options:[.sortedKeys]) == JSONSerialization.data(withJSONObject:value,options:[.sortedKeys]) else { throw Failure.invalidTransition }
        return result
    }
}
