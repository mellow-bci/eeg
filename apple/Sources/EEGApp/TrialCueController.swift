import SwiftUI
import AVFAudio
import EEGCore

/// Injection boundaries for controller tests; production uses the actual model
/// and AVSpeechSynthesizer. No synthetic acquisition mode is exposed in the app.
protocol TrialCueAcquisition: AnyObject {
    var recording:Bool {get}
    var transportStable:Bool {get}
    var trial:EEGTrialEvidence? {get}
    var recordingClock:Double {get}
    func trialObservationTime(uptime:Double)->Double
    func submitTrialBegin(_ planned:EEGTrialEvidence,completion:@escaping(Result<Void,Error>)->Void) throws
    func submitTrialTransition(_ change:(inout EEGTrialEvidence,Double)throws->Void,
                               at:Double?,completion:((Result<Void,Error>)->Void)?) throws
    func cancelTrial(reason:String)
}
protocol TrialSpeechOutput: AnyObject {
    var delegate:AVSpeechSynthesizerDelegate? {get set}
    func speak(_ utterance:AVSpeechUtterance)
    @discardableResult func stopSpeaking(at boundary:AVSpeechBoundary)->Bool
}
extension AVSpeechSynthesizer: TrialSpeechOutput {}

/// Native speech callbacks are observations, not proof that audio was heard.
final class TrialCueController: NSObject, ObservableObject, AVSpeechSynthesizerDelegate {
    @Published var status="Idle"
    @Published var checkCompleted=false
    @Published var busy=false
    private weak var acquisition:(any TrialCueAcquisition)?
    private let speech:any TrialSpeechOutput
    private let uptime:()->Double
    private var utterance:AVSpeechUtterance?
    private enum Purpose {case check,instruction,end,stop}
    private var purpose:Purpose = .check
    private var requestedAt=0.0
    private var timer:Timer?
    private var runID=UUID()
    private var waiting=false
    init(acquisition:any TrialCueAcquisition,speech:any TrialSpeechOutput=AVSpeechSynthesizer(),
         uptime:@escaping()->Double={ProcessInfo.processInfo.systemUptime}) {
        self.acquisition=acquisition;self.speech=speech;self.uptime=uptime;super.init();speech.delegate=self
    }
    deinit {timer?.invalidate()}
    func audioCheck() {
        guard !busy else {return}
        runID=UUID();checkCompleted=false
        speak("EEG audio check. Keep your eyes open. You can stop the trial at any time.",purpose:.check)
    }
    func start(_ planned:EEGTrialEvidence,ready:Bool,heard:Bool) {
        guard !busy,checkCompleted,ready,heard,let acquisition else {return}
        runID=UUID();let run=runID
        checkCompleted=false;busy=true;waiting=true;purpose = .instruction
        status="Saving trial start";monitor()
        do {
            try acquisition.submitTrialBegin(planned) { [weak self] result in
                guard let self,self.runID==run else {return}
                self.waiting=false
                guard case .success=result else {self.stop(reason:"trial_start_save_failed");return}
                self.transition({try $0.requestCue(at:$1,participantReady:ready,audioCheckHeard:heard,
                    transportStable:acquisition.transportStable,recordingActive:acquisition.recording)}) {
                    let task: String
                    switch planned.requestedCondition {
                    case .neutral: task = "Do not subtract. Remain comfortably seated with eyes open."
                    case .silentSerialSubtraction: task = "Starting number \(planned.startingNumber). Silently subtract three repeatedly. Keep your eyes open and do not speak or deliberately move."
                    case .ordinaryActivity: task = "Remain seated with eyes open. Look around naturally and breathe normally. Do not perform the mental task."
                    case .blinkControl: task = "Remain seated and blink comfortably several times. Do not perform the mental task."
                    case .jawControl: task = "Gently open and close your jaw a few times without clenching. Stop if uncomfortable. Do not perform the mental task."
                    case .headMovementControl: task = "Gently turn your head a little left and right while seated. Stop if uncomfortable. Do not perform the mental task."
                    }
                    self.speak("\(task) Begin when this instruction ends.",purpose:.instruction)
                }
            }
        } catch {stop(reason:"trial_start_rejected")}
    }
    private func monitor() {
        requestedAt=uptime()
        timer?.invalidate()
        timer=Timer.scheduledTimer(withTimeInterval:0.1,repeats:true) { [weak self] _ in self?.tick() }
    }
    private func speak(_ text:String,purpose:Purpose) {
        self.purpose=purpose;busy=true;status=text
        let value=AVSpeechUtterance(string:text);value.voice=AVSpeechSynthesisVoice(language:"en-US")
        utterance=value;monitor();speech.speak(value)
    }
    private func transition(_ change:(inout EEGTrialEvidence,Double)throws->Void,
                            at:Double?=nil,then:@escaping()->Void) {
        guard let acquisition else {stop(reason:"acquisition_unavailable");return}
        let run=runID;waiting=true;status="Saving trial evidence";requestedAt=uptime()
        do {
            try acquisition.submitTrialTransition(change,at:at) { [weak self] result in
                guard let self,self.runID==run else {return}
                self.waiting=false
                guard case .success=result,acquisition.recording,acquisition.transportStable else {
                    self.stop(reason:"trial_transition_save_failed");return
                }
                then()
            }
        } catch {stop(reason:"trial_transition_rejected")}
    }
    func tick() {
        guard let acquisition else {stop(reason:"acquisition_unavailable");return}
        if purpose == .instruction || purpose == .end {
            if acquisition.trial?.phase == .interrupted || !acquisition.recording || !acquisition.transportStable {
                stop(reason:"acquisition_interrupted");return
            }
            if let deadline=acquisition.trial?.conditionDeadline,acquisition.trial?.phase == .endRequested,
               acquisition.recordingClock-deadline>EEGTrialEvidence.maximumEndCueDelay {
                stop(reason:"end_cue_start_late");return
            }
            if let deadline=acquisition.trial?.conditionDeadline,acquisition.trial?.phase == .conditionActive {
                let now=acquisition.recordingClock
                if now>=deadline {
                    guard now-deadline<=EEGTrialEvidence.maximumEndCueDelay else {stop(reason:"end_cue_timer_late");return}
                    if !waiting {
                        transition({try $0.requestEndCue(at:$1)}) {
                            self.speak("Stop the task. Please report whether you followed the instruction.",purpose:.end)
                        }
                    }
                }
                return
            }
        }
        if uptime()-requestedAt>EEGTrialEvidence.maximumSpeechDuration {stop(reason:"speech_or_storage_timeout")}
    }
    func stop(reason:String="participant_stopped") {
        let wasStop=purpose == .stop
        runID=UUID();waiting=false;timer?.invalidate();timer=nil;utterance=nil
        speech.stopSpeaking(at:.immediate)
        acquisition?.cancelTrial(reason:reason)
        busy=false;checkCompleted=false;status="Stopped: "+reason
        if !wasStop {speak("The trial has stopped. Stop the task and rest.",purpose:.stop)}
    }
    func speechSynthesizer(_ synthesizer:AVSpeechSynthesizer,didStart value:AVSpeechUtterance) {
        let observed=uptime()
        DispatchQueue.main.async { [weak self] in
            guard let self,self.utterance === value,let acquisition=self.acquisition else {return}
            let at=acquisition.trialObservationTime(uptime:observed)
            if self.purpose == .instruction {self.transition({try $0.cueStarted(at:$1)},at:at) {}}
            if self.purpose == .end {self.transition({try $0.endCueStarted(at:$1)},at:at) {}}
        }
    }
    func speechSynthesizer(_ synthesizer:AVSpeechSynthesizer,didFinish value:AVSpeechUtterance) {
        let observed=uptime()
        DispatchQueue.main.async { [weak self] in
            guard let self,self.utterance === value,let acquisition=self.acquisition else {return}
            let at=acquisition.trialObservationTime(uptime:observed)
            self.utterance=nil
            switch self.purpose {
            case .check:
                self.checkCompleted=true;self.busy=false;self.status="Audio check finished. Confirm whether you heard it.";self.timer?.invalidate()
            case .instruction:
                self.transition({try $0.cueCompleted(at:$1)},at:at) {self.status="Condition period — wait for the spoken end cue."}
            case .end:
                self.transition({try $0.endCueCompleted(at:$1)},at:at) {
                    self.busy=false;self.status="Awaiting your report";self.timer?.invalidate()
                }
            case .stop: self.busy=false;self.status="Trial stopped. New readiness and audio check required.";self.timer?.invalidate()
            }
        }
    }
    func speechSynthesizer(_ synthesizer:AVSpeechSynthesizer,didCancel value:AVSpeechUtterance) {
        DispatchQueue.main.async { [weak self] in
            guard let self,self.utterance === value else {return};self.stop(reason:"speech_cancelled")
        }
    }
    func speechSynthesizer(_ synthesizer:AVSpeechSynthesizer,didPause value:AVSpeechUtterance) {
        DispatchQueue.main.async { [weak self] in
            guard let self,self.utterance === value else {return};self.stop(reason:"speech_paused")
        }
    }
}
