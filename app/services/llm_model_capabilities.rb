# frozen_string_literal: true

module LlmModelCapabilities
  module_function

  def for(model)
    declared = Array(model.capabilities).map { |value| value.to_s.downcase }
    input_modalities = Array(model.modalities.to_h["input"]).map { |value| value.to_s.downcase }
    capabilities = []

    if declared.intersect?(%w[chat text_generation])
      capabilities << :text_generation
      capabilities << :tool_calling
    end
    capabilities << :tool_calling if declared.intersect?(%w[tools tool_calling function_calling])
    capabilities << :vision if input_modalities.intersect?(%w[image vision])
    capabilities << :embedding if declared.intersect?(%w[embedding embeddings])
    capabilities.uniq.freeze
  end
end
