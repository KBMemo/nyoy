# frozen_string_literal: true

module GenerationMemoBodyBuilder
  DEFAULT_TAGS = %w[nyoy ai-image].freeze

  module_function

  def build(source:, attachment:)
    lines = ["# SD 生成メモ", ""]
    lines.concat(source_section(source))
    lines << ""
    lines.concat(prompt_sections(source, attachment))
    lines << ""
    lines.concat(settings_section(source, attachment))
    lines.concat(timing_section(source))
    lines << ""
    lines << "## 如意"
    lines << "- 種別: #{generation_kind_label(source)}"
    lines << "- 詳細: #{source_detail_link(source)}"
    lines.join("\n")
  end

  def title_for(source:, attachment: nil)
    base =
      case source
      when MemoIllustration
        source.body.to_s.lines.first&.strip
      else
        source.try(:japanese_prompt).presence || source.try(:prompt).presence || source.try(:display_summary)
      end

    truncate_title(base)
  end

  def tags_for(source)
    DEFAULT_TAGS + [generation_kind_tag(source)]
  end

  def generation_kind_label(source)
    case source
    when ImageGeneration then "テキスト生成（如意）"
    when MemoIllustration then "メモ挿絵（如意）"
    when Img2imgGeneration then "Img2Img（如意）"
    else source.class.name
    end
  end

  def generation_kind_tag(source)
    case source
    when ImageGeneration then "image-generation"
    when MemoIllustration then "memo-illustration"
    when Img2imgGeneration then "img2img"
    else source.class.name.underscore.dasherize
    end
  end

  def source_section(source)
    case source
    when MemoIllustration
      ["## 入力した文章", "", source.body.to_s.strip]
    when Img2imgGeneration
      lines = []
      if source.source_label.present?
        lines << "## 転記元"
        lines << ""
        lines << source.source_label
      end
      lines
    else
      []
    end
  end

  def prompt_sections(source, attachment)
    lines = []

    if source.try(:japanese_prompt).present?
      lines << "## 日本語プロンプト"
      lines << ""
      lines << source.japanese_prompt.strip
      lines << ""
    end

    prompt = source.try(:positive_prompt).presence || source.try(:prompt).presence
    if prompt.present?
      lines << "## SD プロンプト"
      lines << ""
      lines << prompt.strip
      lines << ""
    end

    negative = source.try(:resolved_negative_prompt).presence
    if negative.present?
      lines << "## ネガティブプロンプト"
      lines << ""
      lines << negative.strip
      lines << ""
    end

    lines.concat(attachment_prompt_sections(source, attachment))
    lines
  end

  def attachment_prompt_sections(source, attachment)
    return [] unless attachment

    case source
    when ImageGeneration
      label = source.refined_image_label(attachment)
      ["## 保存した画像", "", label]
    when MemoIllustration
      return [] unless source.inpainted_attachment?(attachment)

      lines = ["## 部分修正", "", source.inpainted_image_label(attachment)]
      note = source.inpaint_note_for(attachment)
      lines << "日本語指示: #{note}" if note.present?
      full = source.inpaint_prompt_for(attachment)
      lines += ["", "## 修正プロンプト", "", full] if full.present?
      lines
    else
      []
    end
  end

  def timing_section(source)
    return [] unless source.respond_to?(:generation_elapsed_seconds)

    lines = timing_lines(source)
    return [] if lines.empty?

    ["", "## 生成時間", ""] + lines
  end

  def timing_lines(source)
    show_prompt_timing = show_prompt_timing_for(source)
    lines = []

    if source.image_started_at || (show_prompt_timing && source.prompt_started_at)
      if show_prompt_timing && source.prompt_started_at
        lines << "- プロンプト: #{format_duration(source.prompt_elapsed_seconds)}"
      end
      if source.image_started_at
        lines << "- 画像: #{format_duration(source.image_elapsed_seconds)}"
      end
    elsif source.started_at
      lines << "- 合計: #{format_duration(source.generation_elapsed_seconds)}"
    end

    lines
  end

  def show_prompt_timing_for(source)
    !source.is_a?(ImageGeneration)
  end

  def format_duration(seconds)
    return "—" if seconds.nil?

    if seconds < 60
      format("%.1f秒", seconds)
    else
      minutes = (seconds / 60).floor
      remainder = seconds % 60
      format("%d分%.0f秒", minutes, remainder)
    end
  end

  def settings_section(source, attachment)
    lines = ["## 設定", ""]

    case source
    when ImageGeneration
      lines << "- スタイル: #{source.style_label}" if source.style_label.present?
      lines << "- モデル: #{format_model(source)}" if format_model(source).present?
      lines << "- サイズ: #{source.width}×#{source.height}"
      lines << "- ラフ: #{source.draft_batch_size} 枚 / #{source.draft_steps_for_api} steps"
      lines << "- 仕上げ: #{source.refine_steps_for_api} steps / 強度 #{source.refine_denoising_strength}"
      lines << "- Hires: #{source.enable_hires? ? 'ON' : 'OFF'}"
      lines << "- CFG: #{source.cfg_scale}"
      lines << "- Seed: #{format_seed(source.seed)}"
      lines << "- Sampler: #{source.sampler_name}"
    when MemoIllustration
      lines << "- スタイル: #{source.style_label}" if source.style_label.present?
      lines << "- モデル: #{format_model(source)}" if format_model(source).present?
      lines << "- サイズ: #{source.width}×#{source.height}"
      lines << "- Steps / CFG: #{source.steps} / #{source.cfg_scale}"
      lines << "- Seed: #{format_seed(source.seed)}"
    when Img2imgGeneration
      lines << "- モード: #{source.generation_mode_label}"
      lines << "- スタイル: #{source.style_label}" if source.style_label.present?
      lines << "- モデル: #{format_model(source)}" if format_model(source).present?
      lines << "- サイズ: #{source.width}×#{source.height}"
      lines << "- Steps / 強度 / CFG: #{source.steps} / #{source.denoising_strength} / #{source.cfg_scale}"
      lines << "- Seed: #{format_seed(source.seed)}"
      lines << "- Sampler: #{source.sampler_name}"
    end

    lines
  end

  def source_path(source)
    Rails.application.routes.url_helpers.polymorphic_path(source, only_path: true)
  end

  def source_url(source)
    url_options = Rails.application.config.action_mailer.default_url_options || {}
    Rails.application.routes.url_helpers.polymorphic_url(source, **url_options)
  end

  def source_detail_link(source)
    path = source_path(source)
    "[#{path}](#{source_url(source)})"
  end

  def truncate_title(text)
    text = text.to_s.gsub(/\s+/, " ").strip
    return "Nyoy 生成メモ" if text.blank?

    text.length > 60 ? "#{text[0, 57]}..." : text
  end

  def format_seed(seed)
    return "ランダム" if seed.nil? || seed.to_i.negative?

    seed.to_s
  end

  def format_model(source)
    case source
    when ImageGeneration
      label = source.model_label
    else
      key = source.try(:sd_model)
      label = SdModelProfile.find_by(key: key)&.name || key
    end

    label.presence unless label == "—"
  end
end
