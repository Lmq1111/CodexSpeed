# Third-party notices

## swift-tiktoken

- Upstream: https://github.com/DePasqualeOrg/swift-tiktoken
- Vendored commit: `b4310ee520995ddff45b055de19e6605e0f8e5b6`
- License: MIT, Copyright © Anthony DePasquale.
- Full notice: [Vendor/swift-tiktoken/LICENSE](Vendor/swift-tiktoken/LICENSE).
- The local package uses Swift tools version 6.2 for this project; upstream attribution is retained.

## OpenAI tiktoken / o200k_base

- Upstream: https://github.com/openai/tiktoken
- Vocabulary source: https://openaipublic.blob.core.windows.net/encodings/o200k_base.tiktoken
- Bundled file: `Sources/MonitorCore/o200k_base.tiktoken`
- SHA-256: `446a9538cb6c348e3516120d7c08b09f57c36495e2acfffe59a5bf8b0cfb1a2d`
- Ordinary token entries: 199,998.
- Upstream MIT notice: [Vendor/tiktoken-LICENSE](Vendor/tiktoken-LICENSE), Copyright (c) 2022 OpenAI, Shantanu Jain.

The vocabulary is bundled for offline loading. The installer includes these notices and the project license in the app's Resources directory. Neither these attributions nor the use of Codex data imply endorsement by OpenAI or the upstream authors.
