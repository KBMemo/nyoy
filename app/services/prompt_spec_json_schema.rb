# frozen_string_literal: true

class PromptSpecJsonSchema
  def self.build(allowed_loras:, allowed_samplers:, allowed_models:)
    lora_name_schema = if allowed_loras.any?
      { type: "string", enum: allowed_loras }
    else
      { type: "string" }
    end

    sampler_schema = if allowed_samplers.any?
      { type: "string", enum: allowed_samplers }
    else
      { type: "string" }
    end

    model_schema = if allowed_models.any?
      { type: "string", enum: allowed_models }
    else
      { type: "string" }
    end

    {
      type: "json_schema",
      json_schema: {
        name: "prompt_spec",
        strict: true,
        schema: {
          type: "object",
          properties: {
            positive_prompt: { type: "string" },
            negative_prompt: { type: "string" },
            model_family: model_schema,
            width: { type: "integer" },
            height: { type: "integer" },
            steps: { type: "integer" },
            cfg_scale: { type: "number" },
            sampler: sampler_schema,
            seed: { type: "integer" },
            loras: {
              type: "array",
              items: {
                type: "object",
                properties: {
                  name: lora_name_schema,
                  weight: { type: "number" }
                },
                required: %w[name weight],
                additionalProperties: false
              }
            },
            notes_ja: { type: "string" },
            source_chunk_ids: {
              type: "array",
              items: { type: "integer" }
            }
          },
          required: %w[positive_prompt negative_prompt model_family sampler loras source_chunk_ids],
          additionalProperties: false
        }
      }
    }
  end
end
