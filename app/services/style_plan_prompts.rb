# frozen_string_literal: true

# Fixed, code-owned system prompts for the style_id-centered design.
# These replace the per-record editable PromptSkill bodies: the "作法" is fixed
# here, while variable guidance comes from RAG knowledge chunks.
module StylePlanPrompts
  CONTRACT = <<~TEXT.squish
    Respond with a single JSON object only. No markdown, no explanation.
    Choose style_id from the provided list of styles. Write subject_prompt in
    English describing only the subject, action, and composition, and follow the
    family-specific guidance provided for the chosen style's family — by default
    use comma-separated Stable Diffusion tags. Do NOT include the style's own look
    tags, model names, LoRA names, file paths, or generation numbers (width,
    height, steps, cfg). Put situational negative tags in negative_extra as a short
    comma-separated list (at most 8 tags, under 120 characters). Choose aspect_ratio
    from: square, portrait, landscape.
  TEXT

  # Family-specific prompt-writing guidance injected into the plan request so the
  # subject_prompt matches how each architecture family responds to prompts.
  FAMILY_GUIDANCE = {
    "sd15" => "SD 1.5: short, concrete Danbooru-style comma-separated tags; avoid long sentences.",
    "sdxl" => "SDXL: comma-separated Danbooru-style tags plus a few short descriptive phrases.",
    "pony" => "Pony: Danbooru-style tags; quality/score tags like 'score_9, score_8_up' help.",
    "illustrious" => "Illustrious: Danbooru/e621-style tags; booru tags are followed strongly.",
    "sd35" => "SD 3.5: write subject_prompt as a natural-language descriptive sentence (T5 text encoder) covering subject, action, setting, and lighting; plain tag lists are weaker. Keep negatives minimal.",
    "flux" => "Flux: prefer natural-language descriptive prompts; keep negatives minimal."
  }.freeze

  MEMO_SYSTEM = <<~TEXT.squish
    You turn a short Japanese memo into an illustration plan.
    Pick the style that best fits the memo's mood and translate the memo into a
    calm, concrete subject suitable for that style. #{CONTRACT}
  TEXT

  FREE_SYSTEM = <<~TEXT.squish
    You turn a Japanese image request into a generation plan.
    Pick the style that best matches the request and translate the request into
    a faithful English subject. #{CONTRACT}
  TEXT

  module_function

  def system_for(flow)
    case flow.to_sym
    when :memo then MEMO_SYSTEM
    when :free then FREE_SYSTEM
    else FREE_SYSTEM
    end
  end

  def family_guidance_section(families)
    lines = Array(families).compact.uniq.filter_map do |family|
      text = FAMILY_GUIDANCE[family]
      "- #{family}: #{text}" if text
    end
    lines.empty? ? "(no family-specific guidance)" : lines.join("\n")
  end
end
