# frozen_string_literal: true

# Family-level default prompt generation templates for parameter-tab direct generation.
module SdPromptTemplateSeeds
  TEMPLATES = [
    {
      name: "SD 1.5 向け",
      family: "sd15",
      sort_order: 0,
      body: <<~BODY.squish
        Generate comma-separated English Stable Diffusion 1.5 tags and short phrases from the Japanese description.
        Prefer concise danbooru-style tags. Include quality tags when appropriate
        (masterpiece, best quality, highly detailed).
        For negative_prompt, list common SD 1.5 defects: low quality, worst quality, blurry,
        bad anatomy, extra fingers, watermark, text.
      BODY
    },
    {
      name: "SDXL 向け",
      family: "sdxl",
      sort_order: 1,
      body: <<~BODY.squish
        Generate comma-separated English SDXL tags and descriptive phrases from the Japanese description.
        SDXL tolerates slightly longer prompts than SD 1.5; still prefer clear tag clusters.
        Include quality tags when appropriate (masterpiece, best quality).
        For negative_prompt, cover low quality, worst quality, blurry, bad anatomy, watermark, text.
      BODY
    },
    {
      name: "Pony XL 向け",
      family: "pony",
      sort_order: 2,
      body: <<~BODY.squish
        Generate comma-separated English tags for Pony Diffusion XL from the Japanese description.
        Start prompt with score tags when appropriate (score_9, score_8_up, score_7_up).
        Use danbooru-style tags for characters, actions, and composition.
        For negative_prompt, include score_6, score_5, score_4, low quality, worst quality,
        bad anatomy, extra limbs, blurry, watermark.
      BODY
    },
    {
      name: "Illustrious 向け",
      family: "illustrious",
      sort_order: 3,
      body: <<~BODY.squish
        Generate comma-separated English tags for Illustrious XL anime checkpoints from the Japanese description.
        Use clear character, pose, clothing, and background tags. Quality tags are optional.
        For negative_prompt, list low quality, worst quality, blurry, bad anatomy, extra fingers,
        watermark, text, photorealistic when anime is intended.
      BODY
    },
    {
      name: "SD 3.5 向け",
      family: "sd35",
      sort_order: 4,
      body: <<~BODY.squish
        Generate natural English phrases and short clauses suitable for SD 3.5 Medium/Large from the Japanese description.
        Prefer readable sentences over long tag dumps; keep subject and scene clear.
        For negative_prompt, use short natural-language defect lists: low quality, blurry,
        distorted anatomy, watermark, text, oversaturated.
      BODY
    },
    {
      name: "Flux 向け",
      family: "flux",
      sort_order: 5,
      body: <<~BODY.squish
        Generate concise natural English descriptions for Flux txt2img from the Japanese description.
        Use short sentences or comma-separated phrases; avoid excessive quality tag spam.
        Emphasize subject, lighting, composition, and mood.
        For negative_prompt, keep brief: low quality, blurry, distorted, watermark, text, oversaturated.
      BODY
    },
    {
      name: "グローバル既定",
      family: nil,
      sort_order: 99,
      body: <<~BODY.squish
        Generate English Stable Diffusion prompts from Japanese image descriptions.
        Output comma-separated tags and short phrases unless the target model family prefers natural language.
        Include quality tags when appropriate.
        For negative_prompt, list common defects: low quality, worst quality, blurry, bad anatomy, watermark.
      BODY
    }
  ].freeze

  module_function

  def seed!
    TEMPLATES.each do |attrs|
      scope = if attrs[:family].present?
        SdPromptTemplate.for_family(attrs[:family])
      else
        SdPromptTemplate.global
      end

      template = scope.first || SdPromptTemplate.new
      template.assign_attributes(
        name: attrs[:name],
        body: attrs[:body],
        family: attrs[:family],
        sd_model_profile_id: nil,
        sort_order: attrs[:sort_order],
        enabled: true
      )
      template.save!
    end
  end
end
