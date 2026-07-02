# frozen_string_literal: true

class PromptKnowledgeChunk < ApplicationRecord
  SOURCE_PROMPT = "prompt"
  SOURCE_MEMO = "memo"
  SOURCES = [SOURCE_PROMPT, SOURCE_MEMO].freeze

  KINDS = %w[style model lora negative composition camera lighting inpaint memo].freeze
  KIND_LABELS = {
    "style" => "画風",
    "model" => "モデル",
    "lora" => "LoRA",
    "negative" => "ネガティブ",
    "composition" => "構図",
    "camera" => "カメラ",
    "lighting" => "照明",
    "inpaint" => "部分修正",
    "memo" => "徒然メモ"
  }.freeze

  has_neighbors :embedding

  validates :title, :body, presence: true
  validates :kind, inclusion: { in: KINDS }
  validates :source, inclusion: { in: SOURCES }
  validates :style_ref, presence: true, if: -> { kind == "style" }
  validates :external_id, uniqueness: true, allow_nil: true
  validate :style_ref_must_exist, if: -> { style_ref.present? }

  scope :ordered, -> { order(updated_at: :desc, id: :desc) }
  scope :embedded, -> { where.not(embedding: nil) }
  scope :from_prompt, -> { where(source: SOURCE_PROMPT) }
  scope :from_memo, -> { where(source: SOURCE_MEMO) }

  attr_accessor :skip_auto_embed

  after_commit :embed!, on: %i[create update], if: :should_reembed?

  def self.memo_external_id(memo_uid, chunk_index)
    "kbmemo:#{memo_uid}:chunk:#{chunk_index}"
  end

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

  def to_memo_rag_context
    uid = metadata["memo_uid"] || metadata[:memo_uid]
    lines = ["[memo:#{uid}] #{title}"]
    lines << "updated_at: #{metadata['memo_updated_at'] || metadata[:memo_updated_at]}" if metadata.present?
    lines << body
    lines.join("\n")
  end

  private

  def embed!
    vector = PromptKnowledgeChunkEmbedder.new.embed_text(embed_text)
    update_column(:embedding, vector)
  rescue PromptKnowledgeChunkEmbedder::Error => e
    Rails.logger.warn("PromptKnowledgeChunk##{id} embedding failed: #{e.message}")
  end

  def style_ref_must_exist
    return if PromptStyle.exists?(style_id: style_ref)

    errors.add(:style_ref, "は有効な style_id を指定してください")
  end

  def should_reembed?
    return false if skip_auto_embed

    saved_change_to_title? || saved_change_to_body? || embedding.nil?
  end

  def from_memo?
    source == SOURCE_MEMO
  end
end
