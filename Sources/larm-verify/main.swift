import Foundation
import LARMCore

var args = Array(CommandLine.arguments.dropFirst())
var expected: String? = nil
if let i = args.firstIndex(of: "--expect-manifest-sha256"), i + 1 < args.count { expected = args[i + 1]; args.removeSubrange(i...(i + 1)) }
guard let path = args.first else {
    FileHandle.standardError.write(Data("사용법: larm-verify <evidence.zip> [--expect-manifest-sha256 <hex>]\n".utf8))
    exit(2)
}
guard let data = FileManager.default.contents(atPath: path) else {
    FileHandle.standardError.write(Data("파일을 읽을 수 없습니다: \(path)\n".utf8)); exit(2)
}
let report = Verifier.verify(zip: data, expectedManifestSHA256: expected)
print(Verifier.render(report))
exit(report.ok ? 0 : 1)
