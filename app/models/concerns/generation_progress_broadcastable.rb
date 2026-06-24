# frozen_string_literal: true

module GenerationProgressBroadcastable
  extend ActiveSupport::Concern

  included do
    include Turbo::Broadcastable

    after_update_commit :broadcast_progress_panel
  end

  def generation_elapsed_seconds
    return unless started_at

    finish = finished_at || Time.current
    finish - started_at
  end

  def prompt_phase_active?
    in_progress? && status.in?(%w[translating planning])
  end

  def image_phase_active?
    in_progress? && status == "generating"
  end

  def prompt_elapsed_seconds
    phase_elapsed_seconds(
      started_at: prompt_started_at,
      finished_at: prompt_finished_at,
      active: prompt_phase_active?
    )
  end

  def image_elapsed_seconds
    phase_elapsed_seconds(
      started_at: image_started_at,
      finished_at: image_finished_at,
      active: image_phase_active?
    )
  end

  private

  def phase_elapsed_seconds(started_at:, finished_at:, active:)
    return unless started_at

    finish = finished_at || (active ? Time.current : nil)
    return unless finish

    finish - started_at
  end

  def broadcast_progress_panel
    broadcast_replace_to(
      self,
      target: ActionView::RecordIdentifier.dom_id(self, :status),
      partial: progress_panel_partial,
      locals: progress_panel_locals
    )
  end
end
