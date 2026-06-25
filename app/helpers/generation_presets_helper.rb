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
        loras: preset.loras_array,
        draft_batch_size: preset.draft_batch_size,
        draft_steps: preset.draft_steps
      }
    end
  end

  def refine_presets_stimulus_data(presets)
    Array(presets).each_with_object({}) do |preset, hash|
      hash[preset.id] = {
        refine_steps: preset.refine_steps,
        refine_denoising_strength: preset.refine_denoising_strength,
        enable_hires: preset.enable_hires,
        hires_upscaler: preset.hires_upscaler,
        hires_scale: preset.hires_scale,
        hires_steps: preset.hires_steps,
        hires_denoising_strength: preset.hires_denoising_strength
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
