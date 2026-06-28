# frozen_string_literal: true

class PromptSkillDraftJsonSchema
  def self.build
    {
      type: "json_schema",
      json_schema: {
        name: "prompt_skill_draft",
        strict: true,
        schema: {
          type: "object",
          properties: {
            name: { type: "string" },
            body: { type: "string" },
            default_negative_prompt: { type: "string" }
          },
          required: %w[name body default_negative_prompt],
          additionalProperties: false
        }
      }
    }
  end
end
