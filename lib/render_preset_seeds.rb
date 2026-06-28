# frozen_string_literal: true

# Phase 3 (render layer) seeds. Splits the old GenerationPreset draft/refine/hires
# parameters into style-agnostic render pipelines, plus a single-phase pipeline
# for memo illustrations.
module RenderPresetSeeds
  PRESETS = [
    {
      name: "単発（メモ挿絵）",
      kind: "single",
      default: true,
      draft_batch_size: 1,
      draft_steps: nil
    },
    {
      name: "案出し（4枚）",
      kind: "draft",
      default: true,
      draft_batch_size: 4,
      draft_steps: nil
    },
    {
      name: "本番（hires）",
      kind: "refine",
      default: true,
      refine_denoising_strength: 0.4,
      enable_hires: true,
      hires_upscaler: "Latent",
      hires_scale: 1.5,
      hires_denoising_strength: 0.35
    }
  ].freeze

  module_function

  def seed!
    PRESETS.each do |attrs|
      preset = RenderPreset.find_or_initialize_by(name: attrs[:name])
      preset.assign_attributes(attrs)
      preset.save!
    end
  end
end
