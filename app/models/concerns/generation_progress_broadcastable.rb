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

  private

  def broadcast_progress_panel
    broadcast_replace_to(
      self,
      target: ActionView::RecordIdentifier.dom_id(self, :status),
      partial: progress_panel_partial,
      locals: progress_panel_locals
    )
  end
end
