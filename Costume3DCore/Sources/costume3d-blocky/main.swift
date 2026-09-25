// Writes the bundled Blocky rigged model: swift run costume3d-blocky <output.usda>
import Costume3DCore
import Foundation

let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "Blocky.usda"
try USDAWriter.blocky().write(to: URL(fileURLWithPath: out), atomically: true, encoding: .utf8)
print("wrote \(out)")
