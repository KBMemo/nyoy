# frozen_string_literal: true

class PromptRagContext
  def initialize(record:, retriever: PromptKnowledgeRetriever.new, allowed_lists: nil)
    @record = record
    @retriever = retriever
    @allowed_lists = allowed_lists || PromptAllowedLists.new(record: record)
  end

  def call(query)
    chunks = @retriever.retrieve(query).to_a
    allowed = @allowed_lists.call

    {
      chunks: chunks,
      chunk_ids: chunks.map(&:id),
      allowed: allowed,
      chunk_section: chunk_section(chunks),
      preset_section: preset_section(allowed[:prompt_presets]),
      lora_section: lora_section(allowed[:lora_dictionary])
    }
  end

  private

  def chunk_section(chunks)
    if chunks.any?
      chunks.map(&:to_rag_context).join("\n\n---\n\n")
    else
      "(no knowledge chunks matched)"
    end
  end

  def preset_section(presets)
    if presets.any?
      presets.map(&:to_rag_context).join("\n\n---\n\n")
    else
      "(no prompt presets registered)"
    end
  end

  def lora_section(dictionary)
    if dictionary.any?
      dictionary.map(&:to_rag_context).join("\n\n")
    else
      "(no LoRA dictionary entries)"
    end
  end
end
