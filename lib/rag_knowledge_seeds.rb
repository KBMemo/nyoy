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

  EMPHASIS_SYNTAX_GUIDANCE = <<~BODY.strip.freeze
    強調構文（emphasis / attention）で個々のタグの効き目を調整できる。subject_prompt と negative_extra の両方で使用可能。
    括弧 (tag) は影響を強める。角括弧 [tag] は影響を弱める。括弧は重ねるほど強く効くが、最大4つまで（5つ以上は破綻しやすい）。
    数値指定は (tag:1.4) のように「括弧1つ + コロン + 数値」で書く。数値が大きいほど強い。括弧なしの数値のみは効きが弱いので必ず括弧1つで囲む。
    推奨上限: ポジティブ（subject_prompt）は最大 1.4、ネガティブ（negative_extra）は最大 2.0。強調は本当に強めたい少数のタグだけに使い、多用しない。
    使いどころ: 「もっと〜を多く / はっきり」など特定の要素を強めたい時に (flower:1.3) のように書く。逆に控えめにしたい時は [tag] を使う。
    高品質を狙う定番ネガティブ例: (worst quality:1.4), (low quality:1.4)。
  BODY
end
