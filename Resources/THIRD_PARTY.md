macOS-Diktier-App uses the following open-source components:

- whisper.cpp v1.9.4: https://github.com/ggml-org/whisper.cpp (MIT)
- Whisper models: https://github.com/openai/whisper (MIT)
- MLX Audio Swift: https://github.com/Blaizzy/mlx-audio-swift (MIT)
- MLX Swift: https://github.com/ml-explore/mlx-swift (MIT)
- Qwen3-ASR: https://huggingface.co/Qwen/Qwen3-ASR-1.7B (Apache 2.0)
- MLX quantization: https://huggingface.co/mlx-community/Qwen3-ASR-1.7B-8bit
- Swift Transformers / Swift Hugging Face: https://github.com/huggingface (Apache 2.0)
- Swift Crypto / Collections / Numerics / Argument Parser: https://github.com/apple (Apache 2.0)

Dependency revisions are recorded in Engine/Package.resolved.
Model downloads are pinned by SHA-256 in Sources/FlowCore/ModelCatalog.swift.
This is an independent local dictation app and is not affiliated with Wispr Flow.
