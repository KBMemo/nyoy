# frozen_string_literal: true

# LLM output contract for parameter-tab direct generation.
# The LLM returns prompt and negative_prompt only; execution params are resolved server-side.
class DirectPromptJsonSchema
  def self.build
    {
      type: "json_schema",
      json_schema: {
        name: "direct_prompt",
        strict: true,
        schema: {
          type: "object",
          properties: {
            prompt: { type: "string" },
            negative_prompt: { type: "string" }
          },
          required: %w[prompt negative_prompt],
          additionalProperties: false
        }
      }
    }
  end
end
