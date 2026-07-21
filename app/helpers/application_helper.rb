# frozen_string_literal: true

module ApplicationHelper
  def content_max_width_class
    "max-w-3xl"
  end

  def kb_focus_ring
    "kb-focus-ring"
  end

  def kb_field_input_classes
    "kb-input kb-field-input"
  end

  def kb_page_title
    "kb-page-title"
  end

  def kb_section_title
    "kb-section-title"
  end

  def kb_label
    "kb-label"
  end

  SETTINGS_NAV_CONTROLLERS = %w[
    prompt_knowledge_chunks
    prompt_styles
    sd_model_profiles
    sd_prompt_templates
    lora_profiles
    service_connections
    llm_sampling_presets
    llm_usage_assignments
    app_settings
  ].freeze

  def kb_chrome_link_class(controller)
    classes = [ "kb-chrome-link" ]
    classes << "font-semibold" if controller_name == controller
    classes.join(" ")
  end

  def kb_settings_nav_active?
    SETTINGS_NAV_CONTROLLERS.include?(controller_name)
  end

  def kb_chrome_settings_trigger_class
    classes = [ "kb-chrome-link", "kb-chrome-dropdown-trigger", kb_focus_ring ]
    classes << "font-semibold" if kb_settings_nav_active?
    classes.join(" ")
  end

  def kb_chrome_dropdown_item_class(controller)
    classes = [ "kb-chrome-dropdown-item" ]
    classes << "font-semibold" if controller_name == controller
    classes.join(" ")
  end

  def kb_settings_nav_items
    [
      [ "ナレッジ", "prompt_knowledge_chunks", prompt_knowledge_chunks_path ],
      [ "スタイル", "prompt_styles", prompt_styles_path ],
      [ "モデル", "sd_model_profiles", sd_model_profiles_path ],
      [ "生成テンプレート", "sd_prompt_templates", sd_prompt_templates_path ],
      [ "LoRA", "lora_profiles", lora_profiles_path ],
      [ "接続", "service_connections", service_connections_path ],
      [ "サンプリング", "llm_sampling_presets", llm_sampling_presets_path ],
      [ "LLM用途", "llm_usage_assignments", llm_usage_assignments_path ],
      [ "既定モデル", "app_settings", edit_app_settings_path ]
    ]
  end

  def kb_btn_primary_sm
    "kb-chrome-btn-primary kb-btn-sm #{kb_focus_ring}"
  end

  def kb_btn_secondary_sm
    "kb-chrome-btn-secondary kb-btn-sm #{kb_focus_ring}"
  end

  def nyoy_format_duration(seconds)
    return "—" if seconds.nil?

    if seconds < 60
      format("%.1f秒", seconds)
    else
      minutes = (seconds / 60).floor
      remainder = seconds % 60
      format("%d分%.0f秒", minutes, remainder)
    end
  end

  def nyoy_format_seed(seed)
    return "ランダム" if seed.nil? || seed.to_i < 0

    seed.to_s
  end

  def nyoy_sd_prompt_token_label(text)
    SdPromptTokenizer.label(text.to_s)
  end

  def nyoy_sd_prompt_token_over_limit?(text)
    SdPromptTokenizer.over_limit?(text.to_s)
  end

  def nyoy_sd_prompt_token_badge(text)
    text = text.to_s
    return "0 / 75" if text.blank?

    nyoy_sd_prompt_token_label(text)
  end

  def nyoy_blob_image_tag(source, **options)
    path = nyoy_blob_image_path(source)
    return unless path

    image_tag path, **options
  end

  def nyoy_blob_image_path(source)
    if source.is_a?(ActiveStorage::Blob)
      rails_blob_path(source, only_path: true)
    elsif source.is_a?(ActiveStorage::Attachment)
      rails_blob_path(source, only_path: true)
    elsif source.is_a?(ActiveStorage::VariantWithRecord)
      rails_representation_path(source, only_path: true)
    elsif source.respond_to?(:attached?)
      return unless source.attached?

      rails_blob_path(source, only_path: true)
    elsif source.respond_to?(:blob)
      rails_blob_path(source, only_path: true)
    end
  end

  def generation_memo_save_available?
    GeneratedImageMemoSaver.available?
  end

  def nyoy_blob_download_path(source, filename: nil)
    return unless source

    blob = if source.is_a?(ActiveStorage::Attachment)
      source.blob
    elsif source.is_a?(ActiveStorage::Attached::One) || source.is_a?(ActiveStorage::Attached::Many)
      source.blob
    elsif source.respond_to?(:blob)
      source.blob
    else
      source
    end

    rails_blob_path(blob, disposition: "attachment", filename: filename || blob.filename, only_path: true)
  end
end
