// Signs a file with the Ed25519 key in $SIGNING_KEY (base64 raw private key)
// and prints the base64 signature. The app checks it with the public key.
import CryptoKit
import Foundation

guard CommandLine.arguments.count == 2 else {
    FileHandle.standardError.write(Data("usage: sign.swift <file>\n".utf8))
    exit(2)
}
guard let encoded = ProcessInfo.processInfo.environment["SIGNING_KEY"],
      let raw = Data(base64Encoded: encoded.trimmingCharacters(in: .whitespacesAndNewlines))
else {
    FileHandle.standardError.write(Data("SIGNING_KEY is missing or not base64\n".utf8))
    exit(1)
}

let key = try Curve25519.Signing.PrivateKey(rawRepresentation: raw)
let data = try Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1]))
let signature = try key.signature(for: data)
print(signature.base64EncodedString())
