# frozen_string_literal: true

module RenderPresetsHelper
  def refine_presets_stimulus_data(presets)
    render_presets_stimulus_data(presets, kind: "refine")
  end

  def draft_render_presets_stimulus_data(presets)
    render_presets_stimulus_data(presets, kind: "draft")
  end

  def render_presets_stimulus_data(presets, kind:)
    Array(presets).each_with_object({}) do |preset, hash|
      hash[preset.id] =
        case kind.to_s
        when "draft"
          {
            draft_batch_size: preset.draft_batch_size,
            draft_steps: preset.draft_steps
          }
        when "refine"
          {
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
  end
end
