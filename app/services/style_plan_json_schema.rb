# frozen_string_literal: true

# Minimal LLM output contract for the style_id-centered design.
# The LLM only chooses a style and writes the subject; numbers, model paths,
# and LoRA paths are resolved server-side by SdPromptStyleResolver.
class StylePlanJsonSchema
  ASPECT_RATIOS = %w[square portrait landscape].freeze

  def self.build(style_ids:, aspect_ratios: ASPECT_RATIOS)
    style_schema = if style_ids.any?
      { type: "string", enum: style_ids }
    else
      { type: "string" }
    end

    {
      type: "json_schema",
      json_schema: {
        name: "style_plan",
        strict: true,
        schema: {
          type: "object",
          properties: {
            style_id: style_schema,
            subject_prompt: { type: "string" },
            negative_extra: { type: "string" },
            aspect_ratio: { type: "string", enum: aspect_ratios }
          },
          required: %w[style_id subject_prompt negative_extra aspect_ratio],
          additionalProperties: false
        }
      }
    }
  end
end
