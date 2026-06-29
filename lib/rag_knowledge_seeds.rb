# frozen_string_literal: true

module RagKnowledgeSeeds
  CHOJUGIGA_NEGATIVE_GUIDANCE = <<~BODY.strip.freeze
    鳥獣戯画では写実・現代彩色・詳細背景を避ける。
    シーンに応じて photorealistic, 3d, colorful, detailed background などを negative_extra に含める。
    text, watermark, seal, stamp なども必要に応じて negative_extra に入れる。
  BODY

  CHOJUGIGA_NEGATIVE_TEMPLATE = <<~BODY.strip.freeze
    シーンに応じたネガティブ例: photorealistic, 3d, anime cel shading, colorful, vibrant colors, detailed background, human focus, text, watermark
  BODY
end
