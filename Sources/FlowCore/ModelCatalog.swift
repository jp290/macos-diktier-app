import CryptoKit
import Foundation

public struct ModelFile: Sendable {
    public let name: String
    public let bytes: Int64
    public let sha256: String
    public let url: URL

    public init(name: String, bytes: Int64, sha256: String, url: URL) {
        self.name = name
        self.bytes = bytes
        self.sha256 = sha256
        self.url = url
    }

    public static func verify(_ url: URL, expected: ModelFile) throws {
        let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize
        guard Int64(size ?? -1) == expected.bytes else { throw FlowError.invalidDownload }
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hash = SHA256()
        while let data = try handle.read(upToCount: 4_194_304), !data.isEmpty {
            try Task.checkCancellation()
            hash.update(data: data)
        }
        let digest = hash.finalize().map { String(format: "%02x", $0) }.joined()
        guard digest == expected.sha256 else { throw FlowError.invalidDownload }
    }
}

public extension ModelPreset {
    var files: [ModelFile] {
        guard self == .qwen else {
            return [ModelFile(name: filename, bytes: bytes, sha256: sha256, url: downloadURL)]
        }
        return [
            ModelFile(name: "chat_template.json", bytes: 1161, sha256: "75a8cfca24f00de72d796fbfed6858fc9614ef3dabd8696684cc3bc03a9c58ff", url: URL(string: "https://huggingface.co/mlx-community/Qwen3-ASR-1.7B-8bit/resolve/a8379a2e2f9e313c9292cdf1af4055ab56d50d55/chat_template.json")!),
            ModelFile(name: "config.json", bytes: 7188, sha256: "1b76b3b6c655fc54595da025f7a96474ad9fa86363303fbdd61a7d8483ccfaf7", url: URL(string: "https://huggingface.co/mlx-community/Qwen3-ASR-1.7B-8bit/resolve/a8379a2e2f9e313c9292cdf1af4055ab56d50d55/config.json")!),
            ModelFile(name: "generation_config.json", bytes: 142, sha256: "1da527824d81e07118facff437e03f2e24a23311e3bdeb2368973fe77e5f275c", url: URL(string: "https://huggingface.co/mlx-community/Qwen3-ASR-1.7B-8bit/resolve/a8379a2e2f9e313c9292cdf1af4055ab56d50d55/generation_config.json")!),
            ModelFile(name: "merges.txt", bytes: 1671853, sha256: "8831e4f1a044471340f7c0a83d7bd71306a5b867e95fd870f74d0c5308a904d5", url: URL(string: "https://huggingface.co/mlx-community/Qwen3-ASR-1.7B-8bit/resolve/a8379a2e2f9e313c9292cdf1af4055ab56d50d55/merges.txt")!),
            ModelFile(name: "model.safetensors", bytes: 2463307541, sha256: "bf304b009cc7eca79283056f787b44c952d24ac22cec787b39732bba3c23c13c", url: URL(string: "https://huggingface.co/mlx-community/Qwen3-ASR-1.7B-8bit/resolve/a8379a2e2f9e313c9292cdf1af4055ab56d50d55/model.safetensors")!),
            ModelFile(name: "model.safetensors.index.json", bytes: 78968, sha256: "0a5d0ec11188602242ff81a9969883d0fdeb98cd5d85cd1413089d897c201af5", url: URL(string: "https://huggingface.co/mlx-community/Qwen3-ASR-1.7B-8bit/resolve/a8379a2e2f9e313c9292cdf1af4055ab56d50d55/model.safetensors.index.json")!),
            ModelFile(name: "preprocessor_config.json", bytes: 330, sha256: "45e120a4eda2c20c5d7f2ea9354e63536bf35e27aa573fb7cdf78017b378770d", url: URL(string: "https://huggingface.co/mlx-community/Qwen3-ASR-1.7B-8bit/resolve/a8379a2e2f9e313c9292cdf1af4055ab56d50d55/preprocessor_config.json")!),
            ModelFile(name: "tokenizer_config.json", bytes: 12487, sha256: "4942d005604266809309cabc9f4e9cb89ce855d59b14681fdc0e1cc62ea26c4c", url: URL(string: "https://huggingface.co/mlx-community/Qwen3-ASR-1.7B-8bit/resolve/a8379a2e2f9e313c9292cdf1af4055ab56d50d55/tokenizer_config.json")!),
            ModelFile(name: "vocab.json", bytes: 2776833, sha256: "ca10d7e9fb3ed18575dd1e277a2579c16d108e32f27439684afa0e10b1440910", url: URL(string: "https://huggingface.co/mlx-community/Qwen3-ASR-1.7B-8bit/resolve/a8379a2e2f9e313c9292cdf1af4055ab56d50d55/vocab.json")!),
        ]
    }
}
