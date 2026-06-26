# frozen_string_literal: true

class MemoPromptPlanJsonSchema
  def self.build
    {
      type: "json_schema",
      json_schema: {
        name: "memo_prompt_plan",
        strict: true,
        schema: {
          type: "object",
          properties: {
            positive: { type: "string" },
            negative: { type: "string" },
            width: { type: "integer" },
            height: { type: "integer" },
            steps: { type: "integer" },
            cfg_scale: { type: "number" },
            seed: { type: "integer" }
          },
          required: %w[positive negative width height steps cfg_scale seed],
          additionalProperties: false
        }
      }
    }
  end
end
