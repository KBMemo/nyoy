# frozen_string_literal: true

module GenerationPresetsHelper
  def generation_presets_stimulus_data(presets)
    presets.each_with_object({}) do |preset, hash|
      hash[preset.id] = {
        sd_model: preset.sd_model,
        width: preset.width,
        height: preset.height,
        steps: preset.steps,
        cfg_scale: preset.cfg_scale,
        sampler_name: preset.sampler_name,
        vae_tiling: preset.vae_tiling,
        prompt_skill_id: preset.prompt_skill_id,
        default_negative_prompt: preset.resolved_default_negative_prompt,
        loras: preset.loras_array
      }
    end
  end

  def sd_loras_stimulus_data(loras)
    Array(loras).map do |entry|
      {
        name: entry["name"],
        path: entry["path"]
      }
    end
  end
end
