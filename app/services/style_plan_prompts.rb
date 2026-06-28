# frozen_string_literal: true

# Fixed, code-owned system prompts for the style_id-centered design.
# These replace the per-record editable PromptSkill bodies: the "作法" is fixed
# here, while variable guidance comes from RAG knowledge chunks.
module StylePlanPrompts
  CONTRACT = <<~TEXT.squish
    Respond with a single JSON object only. No markdown, no explanation.
    Choose style_id from the provided list of styles. Write subject_prompt as
    comma-separated English Stable Diffusion tags describing only the subject,
    action, and composition — do NOT include the style's own look tags, model
    names, LoRA names, file paths, or generation numbers (width, height, steps,
    cfg). Put only situational extra negatives in negative_extra; fixed negatives
    are applied automatically. Choose aspect_ratio from: square, portrait, landscape.
  TEXT

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
end
