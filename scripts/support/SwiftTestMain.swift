import Darwin
import Testing

@main
struct AavAISwiftTestMain {
    static func main() async {
        var arguments = Testing.__CommandLineArguments_v0()
        arguments.parallel = false
        arguments.verbosity = 1
        let result: CInt = await Testing.__swiftPMEntryPoint(passing: arguments)
        exit(result)
    }
}
