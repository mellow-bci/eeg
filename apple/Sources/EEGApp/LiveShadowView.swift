import SwiftUI
import EEGCore

struct LiveShadowView: View {
    let profile: EEGMentalProfile
    @EnvironmentObject private var model: AcquisitionModel
    @State private var sessionID = ""
    @State private var confirmed = false
    @AppStorage("eeg.shadow.maximumPendingInputs") private var inputLimit = "512"
    @AppStorage("eeg.shadow.maximumPendingEventBytes") private var eventByteLimit = "4194304"
    private var validLimits: Bool {
        (Int(inputLimit).map { $0 > 0 } ?? false) && (Int(eventByteLimit).map { $0 > 0 } ?? false)
    }
    @State private var failure: String?
    var body: some View {
        VStack(alignment:.leading,spacing:12) {
            Divider()
            Text("Live shadow inference").font(.headline)
            Text("Processes the connected headset locally using this profile. Candidates are unvalidated, cannot control the system and are recorded separately from measurements.").foregroundStyle(.secondary)
            TextField("New shadow session identity",text:$sessionID).disabled(model.shadowActive)
            Toggle("The wearer is the profile participant: " + profile.participantID,isOn:$confirmed).disabled(model.shadowActive)
            DisclosureGroup("Processing limits") {
                TextField("Maximum pending inputs",text:$inputLimit)
                TextField("Maximum pending event bytes",text:$eventByteLimit)
                Text("Positive whole numbers. Larger queues can retain more data and increase delay. These limits apply to inference; they do not limit recording duration.").font(.caption).foregroundStyle(.secondary)
                if !validLimits { Text("Enter positive whole numbers within the supported integer range.").foregroundStyle(.red) }
                Button("Restore defaults") { inputLimit="512";eventByteLimit="4194304" }
            }.disabled(model.shadowActive)
            HStack {
                Button("Start shadow inference") {
                    do {
                        guard let inputs=Int(inputLimit),let bytes=Int(eventByteLimit),validLimits else { throw EEGLiveInference.Failure.invalidCapacity }
                        try model.startShadow(profile:profile,sessionID:sessionID,participantConfirmed:confirmed,
                            maximumPendingInputs:inputs,maximumPendingEventBytes:bytes)
                        confirmed=false;failure=nil
                    }
                    catch { failure="Start rejected: \(error)" }
                }.disabled(model.shadowActive || !model.recording || !model.ready || !model.transportStable || !confirmed || !validLimits)
                Button("Stop shadow inference") { model.stopShadow() }.disabled(!model.shadowActive)
            }
            Text(model.shadowStatus)
            if let row=model.shadowResult {
                LabeledContent("Window",value:String(row.ordinal))
                LabeledContent("Interpretation",value:row.interpretationLabel)
                Text("No reliable command · system control disabled").font(.caption)
                Text(row.reasons.joined(separator:", ")).font(.caption)
            }
            if let failure { Text(failure).foregroundStyle(.red) }
            Text("Requires an active recording. Loss of continuity, overload or profile closure stops inference; restart is explicit. Session identity is your assertion, not proof of held-out acquisition.").font(.caption).foregroundStyle(.secondary)
        }.onDisappear { model.stopShadow(reason:"profile_view_closed") }
    }
}
