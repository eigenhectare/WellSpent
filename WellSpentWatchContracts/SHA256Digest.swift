import Foundation

public struct SHA256Digest: Equatable, Hashable, Sendable {
    public static let byteCount = 32

    public let bytes: [UInt8]

    public init(bytes: [UInt8]) throws {
        guard bytes.count == Self.byteCount else {
            throw ContractWireError.invalidEnvelope
        }
        self.bytes = bytes
    }

    public init(hex: String) throws {
        guard hex.count == Self.byteCount * 2 else {
            throw ContractWireError.invalidEnvelope
        }

        var parsedBytes: [UInt8] = []
        parsedBytes.reserveCapacity(Self.byteCount)
        var index = hex.startIndex
        for _ in 0..<Self.byteCount {
            let nextIndex = hex.index(index, offsetBy: 2)
            guard let byte = UInt8(hex[index..<nextIndex], radix: 16) else {
                throw ContractWireError.invalidEnvelope
            }
            parsedBytes.append(byte)
            index = nextIndex
        }
        self.bytes = parsedBytes
    }

    public var hex: String {
        bytes.map { String(format: "%02x", $0) }.joined()
    }

    public static func hashing(_ data: Data) -> Self {
        Self(validatedBytes: PureSwiftSHA256.hash(Array(data)))
    }

    private init(validatedBytes: [UInt8]) {
        bytes = validatedBytes
    }
}

extension SHA256Digest: Codable {
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        try self.init(hex: container.decode(String.self))
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(hex)
    }
}

private enum PureSwiftSHA256 {
    private static let initialHash: [UInt32] = [
        0x6a09_e667, 0xbb67_ae85, 0x3c6e_f372, 0xa54f_f53a,
        0x510e_527f, 0x9b05_688c, 0x1f83_d9ab, 0x5be0_cd19,
    ]

    private static let constants: [UInt32] = [
        0x428a_2f98, 0x7137_4491, 0xb5c0_fbcf, 0xe9b5_dba5, 0x3956_c25b, 0x59f1_11f1,
        0x923f_82a4, 0xab1c_5ed5, 0xd807_aa98, 0x1283_5b01, 0x2431_85be, 0x550c_7dc3,
        0x72be_5d74, 0x80de_b1fe, 0x9bdc_06a7, 0xc19b_f174, 0xe49b_69c1, 0xefbe_4786,
        0x0fc1_9dc6, 0x240c_a1cc, 0x2de9_2c6f, 0x4a74_84aa, 0x5cb0_a9dc, 0x76f9_88da,
        0x983e_5152, 0xa831_c66d, 0xb003_27c8, 0xbf59_7fc7, 0xc6e0_0bf3, 0xd5a7_9147,
        0x06ca_6351, 0x1429_2967, 0x27b7_0a85, 0x2e1b_2138, 0x4d2c_6dfc, 0x5338_0d13,
        0x650a_7354, 0x766a_0abb, 0x81c2_c92e, 0x9272_2c85, 0xa2bf_e8a1, 0xa81a_664b,
        0xc24b_8b70, 0xc76c_51a3, 0xd192_e819, 0xd699_0624, 0xf40e_3585, 0x106a_a070,
        0x19a4_c116, 0x1e37_6c08, 0x2748_774c, 0x34b0_bcb5, 0x391c_0cb3, 0x4ed8_aa4a,
        0x5b9c_ca4f, 0x682e_6ff3, 0x748f_82ee, 0x78a5_636f, 0x84c8_7814, 0x8cc7_0208,
        0x90be_fffa, 0xa450_6ceb, 0xbef9_a3f7, 0xc671_78f2,
    ]

    static func hash(_ input: [UInt8]) -> [UInt8] {
        var message = input
        let bitLength = UInt64(message.count) * 8
        message.append(0x80)
        while message.count % 64 != 56 {
            message.append(0)
        }
        message.append(contentsOf: withUnsafeBytes(of: bitLength.bigEndian, Array.init))

        var hash = initialHash
        for chunkStart in stride(from: 0, to: message.count, by: 64) {
            var words = [UInt32](repeating: 0, count: 64)
            for index in 0..<16 {
                let offset = chunkStart + index * 4
                words[index] =
                    UInt32(message[offset]) << 24
                    | UInt32(message[offset + 1]) << 16
                    | UInt32(message[offset + 2]) << 8
                    | UInt32(message[offset + 3])
            }
            for index in 16..<64 {
                let value15 = words[index - 15]
                let value2 = words[index - 2]
                let sigma0 =
                    rotateRight(value15, by: 7) ^ rotateRight(value15, by: 18)
                    ^ (value15 >> 3)
                let sigma1 =
                    rotateRight(value2, by: 17) ^ rotateRight(value2, by: 19)
                    ^ (value2 >> 10)
                words[index] = words[index - 16] &+ sigma0 &+ words[index - 7] &+ sigma1
            }

            var a = hash[0]
            var b = hash[1]
            var c = hash[2]
            var d = hash[3]
            var e = hash[4]
            var f = hash[5]
            var g = hash[6]
            var h = hash[7]

            for index in 0..<64 {
                let upperSigma1 =
                    rotateRight(e, by: 6) ^ rotateRight(e, by: 11)
                    ^ rotateRight(e, by: 25)
                let choice = (e & f) ^ ((~e) & g)
                let temporary1 = h &+ upperSigma1 &+ choice &+ constants[index] &+ words[index]
                let upperSigma0 =
                    rotateRight(a, by: 2) ^ rotateRight(a, by: 13)
                    ^ rotateRight(a, by: 22)
                let majority = (a & b) ^ (a & c) ^ (b & c)
                let temporary2 = upperSigma0 &+ majority

                h = g
                g = f
                f = e
                e = d &+ temporary1
                d = c
                c = b
                b = a
                a = temporary1 &+ temporary2
            }

            hash[0] &+= a
            hash[1] &+= b
            hash[2] &+= c
            hash[3] &+= d
            hash[4] &+= e
            hash[5] &+= f
            hash[6] &+= g
            hash[7] &+= h
        }

        return hash.flatMap { word in
            withUnsafeBytes(of: word.bigEndian, Array.init)
        }
    }

    private static func rotateRight(_ value: UInt32, by amount: UInt32) -> UInt32 {
        (value >> amount) | (value << (32 - amount))
    }
}
