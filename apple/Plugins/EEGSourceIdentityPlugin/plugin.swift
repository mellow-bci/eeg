import PackagePlugin

@main
struct EEGSourceIdentityPlugin: BuildToolPlugin {
    func createBuildCommands(context: PluginContext, target: Target) throws -> [Command] {
        guard let source = target as? SourceModuleTarget else { return [] }
        let root = context.package.directory
        let inputs = source.sourceFiles.map(\.path) + [
            root.appending("Package.swift"),
            root.appending("Plugins/EEGSourceIdentityPlugin/plugin.swift"),
            root.appending("Tools/EEGSourceIdentityTool/main.swift")]
        let output = context.pluginWorkDirectory.appending("EEGSourceIdentity.swift")
        return [.buildCommand(displayName: "Fingerprint EEGCore source inputs",
            executable: try context.tool(named: "EEGSourceIdentityTool").path,
            arguments: [root.string, output.string] + inputs.map(\.string).sorted(),
            inputFiles: inputs, outputFiles: [output])]
    }
}
