# frozen_string_literal: true

class PromptKnowledgeChunk < ApplicationRecord
  KINDS = %w[style model lora negative composition camera lighting].freeze
  KIND_LABELS = {
    "style" => "画風",
    "model" => "モデル",
    "lora" => "LoRA",
    "negative" => "ネガティブ",
    "composition" => "構図",
    "camera" => "カメラ",
    "lighting" => "照明"
  }.freeze

  has_neighbors :embedding

  validates :title, :body, presence: true
  validates :kind, inclusion: { in: KINDS }

  scope :ordered, -> { order(updated_at: :desc, id: :desc) }
  scope :embedded, -> { where.not(embedding: nil) }

  after_commit :embed!, on: %i[create update], if: :should_reembed?

  def kind_label
    KIND_LABELS.fetch(kind, kind)
  end

  def embed_text
    [title, body].join("\n\n")
  end

  def to_rag_context
    <<~TEXT.strip
      [#{id}] #{kind_label}: #{title}
      #{body}
    TEXT
  end

  private

  def should_reembed?
    saved_change_to_title? || saved_change_to_body? || embedding.nil?
  end

  def embed!
    vector = PromptKnowledgeChunkEmbedder.new.embed_text(embed_text)
    update_column(:embedding, vector)
  rescue PromptKnowledgeChunkEmbedder::Error => e
    Rails.logger.warn("PromptKnowledgeChunk##{id} embedding failed: #{e.message}")
  end
end
