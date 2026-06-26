# frozen_string_literal: true

module RagKnowledgeSeeds
  CHOJUGIGA_NEGATIVE_GUIDANCE = <<~BODY.strip.freeze
    鳥獣戯画では写実・現代彩色・詳細背景を避ける。
    シーンに応じて photorealistic, 3d, colorful, detailed background などを negative_prompt に追加する。
    text, watermark, seal, stamp などの固定抑制 tag は実行時に自動適用されるため、JSON の negative_prompt には重複させない。
  BODY

  CHOJUGIGA_NEGATIVE_TEMPLATE = <<~BODY.strip.freeze
    シーンに応じた追加ネガティブ例: photorealistic, 3d, anime cel shading, colorful, vibrant colors, detailed background, human focus
    固定 tag（text, watermark, seal 等）は実行時に適用されるため、ここでは situational な tag のみを negative_prompt に出力する。
  BODY
end
