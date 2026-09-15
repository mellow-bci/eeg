import SwiftUI
import EEGCore

struct TrialCaptureView: View {
    @ObservedObject var model: AcquisitionModel
    @ObservedObject var cues: TrialCueController
    @State private var controls = false
    @State private var participant = ""
    @State private var session = ""
    @State private var ready = false
    @State private var heard = false
    @State private var reviewer = ""
    @State private var reason = ""
    @State private var error: String?
    var body: some View {
        Panel(title: "Planned research session") {
            Text("Save a balanced 24-trial order before the first cue. Each trial requires fresh readiness, a report and review. Only reviewed trials can be exported. Physiological qualification remains pending.").foregroundStyle(.secondary)
            TextField("Participant pseudonym", text: $participant).disabled(model.trialPlan != nil || model.savingTrialPlan)
            TextField("Independent session ID", text: $session).disabled(model.trialPlan != nil || model.savingTrialPlan)
            Toggle("Artifact-control evaluation session",isOn:$controls).disabled(model.trialPlan != nil || model.savingTrialPlan)
            Text(controls ? "Six trials each: ordinary seated activity, blinking, gentle jaw movement and gentle head movement. Evaluation only; these are not mental commands." : "Twelve neutral and twelve silent-subtraction trials.").font(.caption)
            Button("Save session plan") {
                do { try model.commitTrialPlan(participantID: participant,sessionID: session,controls:controls);error=nil }
                catch { self.error=error.localizedDescription }
            }.disabled(!model.recording || model.trialPlan != nil || model.savingTrialPlan)
            if model.savingTrialPlan {ProgressView("Saving session plan")}
            if model.savingTrialRevision {ProgressView("Saving trial evidence")}
            if let plan=model.trialPlan {
                Text("Seed: " + plan.seed).font(.caption.monospaced()).textSelection(.enabled)
                Text("Trials started: \(model.trialsStarted) / 24. At least 10 seconds rest after review; 60 seconds after each block of eight.")
            }
            Button("Play audio check") { ready=false;heard=false;cues.audioCheck() }.disabled(cues.busy)
            Toggle("I heard the completed audio check", isOn: $heard).disabled(!cues.checkCompleted)
            Toggle("Participant is ready now and understands how to stop", isOn: $ready)
            Text(cues.status).accessibilityLabel("Cue status: " + cues.status)
            HStack {
                Button("Start trial") {
                    do {
                        let planned = try model.nextPlannedTrial()
                        cues.start(planned, ready: ready, heard: heard);ready=false;heard=false
                    } catch { self.error=error.localizedDescription }
                }.disabled(!ready || !heard || !cues.checkCompleted || cues.busy || !model.recording || !model.transportStable || participant.trimmingCharacters(in: .whitespaces).isEmpty || session.trimmingCharacters(in: .whitespaces).isEmpty || active || model.trialPlan == nil || model.trialsStarted >= 24)
                Button("Stop trial", role: .destructive) { cues.stop() }.disabled(!active && !cues.busy)
            }
            Text("Requires an active recording with stable transport. Keep eyes open. Reports and reviews must occur after the end cue; they are not objective evidence of a mental state.").font(.caption).foregroundStyle(.secondary)
            if let trial=model.trial {
                Text(trial.id).font(.caption.monospaced()).textSelection(.enabled)
                LabeledContent("Requested condition", value: conditionName(trial.requestedCondition))
                if trial.isControl {
                    Text("Artifact-control trial · evaluation only. Acceptance records the reported activity, not verified movement or mental intent.").font(.caption)
                }
                if let report = trial.participantReport { LabeledContent("Participant report", value: reportName(report)) }
                LabeledContent("Trial state", value: trial.phase.rawValue)
                if trial.phase == .awaitingReport {
                    HStack {
                        reportButton("Attempted", .attempted)
                        reportButton("Uncertain", .uncertain)
                        reportButton("Not attempted", .notAttempted)
                        reportButton("Missed cue", .missedCue)
                    }
                }
                if trial.phase == .reported {
                    TextField("Reviewer identity", text: $reviewer)
                    TextField("Evidence and acceptance/exclusion reason", text: $reason)
                    Text("Behavioral observation: unknown. No camera or movement sensor was used.").font(.caption)
                    HStack {
                        Button("Accept reported condition") { review(true) }.disabled(trial.participantReport != .attempted || reviewMissing || model.savingTrialRevision)
                        Button("Exclude trial") { review(false) }.disabled(reviewMissing || model.savingTrialRevision)
                    }
                }
                if let reason=trial.reviewReason { Text(reason).font(.caption) }
            }
            if let error { Text(error).foregroundStyle(.red).textSelection(.enabled) }
        }
        .onChange(of: model.trial?.id) { _,_ in
            reason = ""; error = nil; ready = false; heard = false
        }
    }
    private func conditionName(_ condition: EEGTrialEvidence.Condition) -> String {
        switch condition {
        case .neutral: return "Neutral, eyes open"
        case .silentSerialSubtraction: return "Silent serial subtraction"
        case .ordinaryActivity: return "Ordinary seated activity"
        case .blinkControl: return "Blink control"
        case .jawControl: return "Gentle jaw movement control"
        case .headMovementControl: return "Gentle head movement control"
        }
    }
    private func reportName(_ report: EEGTrialEvidence.ParticipantReport) -> String {
        switch report {
        case .attempted: return "Attempted"
        case .uncertain: return "Uncertain"
        case .notAttempted: return "Not attempted"
        case .missedCue: return "Missed cue"
        }
    }
    private var active: Bool { model.trial.map { $0.phase != .reviewed && $0.phase != .interrupted } ?? false }
    private var reviewMissing: Bool { reviewer.trimmingCharacters(in: .whitespaces).isEmpty || reason.trimmingCharacters(in: .whitespaces).isEmpty }
    private func reportButton(_ title: String, _ report: EEGTrialEvidence.ParticipantReport) -> some View {
        Button(title) { perform { try $0.report(report, at: $1) } }.disabled(model.savingTrialRevision)
    }
    private func review(_ accept: Bool) { perform { try $0.review(accept: accept, reviewer: reviewer, reason: reason, at: $1) } }
    private func perform(_ change: (inout EEGTrialEvidence, Double) throws -> Void) {
        do { try model.submitTrialTransition(change);error=nil } catch { self.error=error.localizedDescription }
    }
}
