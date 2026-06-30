# frozen_string_literal: true

class PromptKnowledgeChunk < ApplicationRecord
  KINDS = %w[style model lora negative composition camera lighting inpaint].freeze
  KIND_LABELS = {
    "style" => "画風",
    "model" => "モデル",
    "lora" => "LoRA",
    "negative" => "ネガティブ",
    "composition" => "構図",
    "camera" => "カメラ",
    "lighting" => "照明",
    "inpaint" => "部分修正"
  }.freeze

  has_neighbors :embedding

  validates :title, :body, presence: true
  validates :kind, inclusion: { in: KINDS }
  validates :style_ref, presence: true, if: -> { kind == "style" }
  validate :style_ref_must_exist, if: -> { style_ref.present? }

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
    lines = ["[#{id}] #{kind_label}: #{title}"]
    lines << "style_ref: #{style_ref}" if style_ref.present?
    lines << body
    lines.join("\n")
  end

  private

  def style_ref_must_exist
    return if PromptStyle.exists?(style_id: style_ref)

    errors.add(:style_ref, "は有効な style_id を指定してください")
  end

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
