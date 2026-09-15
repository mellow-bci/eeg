import SwiftUI
import AVFAudio
import EEGCore

/// Native speech callbacks are timing observations, not proof the user heard audio.
final class TrialCueController: NSObject, ObservableObject, AVSpeechSynthesizerDelegate {
    @Published var status = "Idle"
    @Published var checkCompleted = false
    @Published var busy = false
    private weak var acquisition: AcquisitionModel?
    private let speech = AVSpeechSynthesizer()
    private var utterance: AVSpeechUtterance?
    private enum Purpose { case check, instruction, end, stop }
    private var purpose: Purpose = .check
    private var requestedAt = 0.0
    private var timer: Timer?
    init(acquisition: AcquisitionModel) {
        self.acquisition = acquisition
        super.init(); speech.delegate = self
    }
    deinit { timer?.invalidate() }
    func audioCheck() {
        guard !busy else { return }
        checkCompleted = false
        speak("EEG audio check. Keep your eyes open. You can stop the trial at any time.", purpose: .check)
    }
    func start(_ planned: EEGTrialEvidence, ready: Bool, heard: Bool) {
        guard !busy,checkCompleted,ready,heard,let acquisition else { return }
        do {
            try acquisition.beginTrial(planned)
            try acquisition.transitionTrial { try $0.requestCue(at: $1, participantReady: ready, audioCheckHeard: heard, transportStable: acquisition.transportStable, recordingActive: acquisition.recording) }
            checkCompleted = false
            let task = planned.requestedCondition == .neutral
                ? "Do not subtract. Remain comfortably seated with eyes open."
                : "Silently subtract three repeatedly. Keep your eyes open and do not speak or deliberately move."
            speak("Starting number \(planned.startingNumber). \(task) Begin when this instruction ends.", purpose: .instruction)
        } catch { status = "Cannot start: " + error.localizedDescription }
    }
    private func speak(_ text: String, purpose: Purpose) {
        self.purpose = purpose; busy = true; status = text
        let value = AVSpeechUtterance(string: text)
        value.voice = AVSpeechSynthesisVoice(language: "en-US")
        utterance = value; requestedAt = ProcessInfo.processInfo.systemUptime
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in self?.tick() }
        speech.speak(value)
    }
    private func tick() {
        guard let acquisition else { stop(reason: "acquisition_unavailable");return }
        if purpose == .instruction || purpose == .end {
            if acquisition.trial?.phase == .interrupted || !acquisition.recording || !acquisition.transportStable {
                stop(reason: "acquisition_interrupted");return
            }
            if let deadline = acquisition.trial?.conditionDeadline, acquisition.trial?.phase == .conditionActive {
                let now = acquisition.recordingClock
                if now >= deadline {
                    // Independent operational tolerance, not a recovered Cortex parameter.
                    guard now-deadline <= EEGTrialEvidence.maximumEndCueDelay else { stop(reason: "end_cue_timer_late");return }
                    do {
                        try acquisition.transitionTrial { try $0.requestEndCue(at: $1) }
                        speak("Stop the task. Please report whether you followed the instruction.", purpose: .end)
                    } catch { stop(reason: "end_cue_transition_failed") }
                }
                return
            }
        }
        if ProcessInfo.processInfo.systemUptime-requestedAt > EEGTrialEvidence.maximumSpeechDuration { stop(reason: "speech_callback_timeout") }
    }
    func stop(reason: String = "participant_stopped") {
        let wasStop = purpose == .stop
        timer?.invalidate();timer=nil;utterance=nil
        speech.stopSpeaking(at: .immediate)
        if let acquisition,let trial=acquisition.trial,trial.phase != .reviewed,trial.phase != .interrupted {
            try? acquisition.transitionTrial { try $0.interrupt(reason: reason, at: $1) }
        }
        busy=false;checkCompleted=false;status="Stopped: " + reason
        if !wasStop { speak("The trial has stopped. Stop the task and rest.", purpose: .stop) }
        // Visible status is authoritative if the output route cannot play speech.
    }
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didStart value: AVSpeechUtterance) {
        DispatchQueue.main.async { [weak self] in
            guard let self,self.utterance === value else { return }
            do {
                if self.purpose == .instruction { try self.acquisition?.transitionTrial { try $0.cueStarted(at: $1) } }
                if self.purpose == .end { try self.acquisition?.transitionTrial { try $0.endCueStarted(at: $1) } }
            } catch { self.stop(reason: "speech_start_transition_failed") }
        }
    }
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish value: AVSpeechUtterance) {
        DispatchQueue.main.async { [weak self] in
            guard let self,self.utterance === value else { return }
            do {
                switch self.purpose {
                case .check: self.checkCompleted=true;self.busy=false;self.status="Audio check finished. Confirm whether you heard it.";self.timer?.invalidate()
                case .instruction:
                    try self.acquisition?.transitionTrial { try $0.cueCompleted(at: $1) }
                    self.status="Condition period — wait for the spoken end cue."
                case .end:
                    try self.acquisition?.transitionTrial { try $0.endCueCompleted(at: $1) }
                    self.busy=false;self.status="Awaiting your report";self.timer?.invalidate()
                case .stop: self.busy=false;self.status="Trial stopped. New readiness and audio check required.";self.timer?.invalidate()
                }
                self.utterance=nil
            } catch { self.stop(reason: "speech_completion_transition_failed") }
        }
    }
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel value: AVSpeechUtterance) {
        DispatchQueue.main.async { [weak self] in
            guard let self,self.utterance === value else { return }
            self.stop(reason: "speech_cancelled")
        }
    }
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didPause value: AVSpeechUtterance) {
        DispatchQueue.main.async { [weak self] in
            guard let self,self.utterance === value else { return }
            self.stop(reason: "speech_paused")
        }
    }
}
