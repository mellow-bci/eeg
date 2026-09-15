import SwiftUI
import EEGCore

struct LiveShadowView: View {
    let profile: EEGMentalProfile
    @EnvironmentObject private var model: AcquisitionModel
    @State private var sessionID = ""
    @State private var confirmed = false
    @State private var failure: String?
    var body: some View {
        VStack(alignment:.leading,spacing:12) {
            Divider()
            Text("Live shadow inference").font(.headline)
            Text("Processes the connected headset locally using this profile. Candidates are unvalidated, cannot control the system and are recorded separately from measurements.").foregroundStyle(.secondary)
            TextField("New shadow session identity",text:$sessionID).disabled(model.shadowActive)
            Toggle("The wearer is the profile participant: " + profile.participantID,isOn:$confirmed).disabled(model.shadowActive)
            HStack {
                Button("Start shadow inference") {
                    do { try model.startShadow(profile:profile,sessionID:sessionID,participantConfirmed:confirmed);confirmed=false;failure=nil }
                    catch { failure="Start rejected: \(error)" }
                }.disabled(model.shadowActive || !model.recording || !model.ready || !model.transportStable || !confirmed)
                Button("Stop shadow inference") { model.stopShadow() }.disabled(!model.shadowActive)
            }
            Text(model.shadowStatus)
            if let row=model.shadowResult {
                LabeledContent("Window",value:String(row.ordinal))
                LabeledContent("Experimental candidate",value:row.candidate ?? "None")
                Text(row.reasons.joined(separator:", ")).font(.caption)
            }
            if let failure { Text(failure).foregroundStyle(.red) }
            Text("Requires an active recording. Loss of continuity, overload or profile closure stops inference; restart is explicit. Session identity is your assertion, not proof of held-out acquisition.").font(.caption).foregroundStyle(.secondary)
        }.onDisappear { model.stopShadow(reason:"profile_view_closed") }
    }
}
