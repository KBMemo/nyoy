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

  def kb_chrome_link_class(controller)
    classes = ["kb-chrome-link"]
    classes << "font-semibold" if controller_name == controller
    classes.join(" ")
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
end
