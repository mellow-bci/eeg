import SwiftUI
import UniformTypeIdentifiers
#if os(macOS)
import AppKit
#endif

/// One platform document-opening adapter. Each consumer retains its own strict
/// schema/size/provenance validator; picking a file does not accept its contents.
private struct EEGJSONDocumentImporter: ViewModifier {
    @Binding var isPresented: Bool
    let completion: (Result<URL,Error>)->Void
    #if os(macOS)
    @State private var panel: NSOpenPanel?
    #endif
    func body(content: Content) -> some View {
        #if os(macOS)
        content
            .onChange(of:isPresented) { _,presented in
                if presented {open()} else {panel?.cancel(nil)}
            }
            .onDisappear {panel?.cancel(nil);panel=nil;isPresented=false}
        #else
        content.fileImporter(isPresented:$isPresented,allowedContentTypes:[.json],onCompletion:completion)
        #endif
    }
    #if os(macOS)
    private func open() {
        guard panel == nil else {return}
        let next=NSOpenPanel()
        next.canChooseFiles=true;next.canChooseDirectories=false
        next.allowsMultipleSelection=false;next.allowedContentTypes=[.json]
        panel=next
        next.begin { response in
            panel=nil;isPresented=false
            if response == .OK,let url=next.url {completion(.success(url))}
        }
    }
    #endif
}

extension View {
    func eegJSONImporter(isPresented:Binding<Bool>,completion:@escaping (Result<URL,Error>)->Void) -> some View {
        modifier(EEGJSONDocumentImporter(isPresented:isPresented,completion:completion))
    }
}
