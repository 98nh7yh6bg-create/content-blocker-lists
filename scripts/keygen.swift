// Makes a new Ed25519 signing key pair. The private key goes into the
// repository's SIGNING_KEY secret; the public key goes into the app.
// Rotating it means shipping an app update with the new public key.
import CryptoKit
import Foundation

let key = Curve25519.Signing.PrivateKey()
print("private: \(key.rawRepresentation.base64EncodedString())")
print("public:  \(key.publicKey.rawRepresentation.base64EncodedString())")
