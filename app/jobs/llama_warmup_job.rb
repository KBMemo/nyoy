# frozen_string_literal: true

class LlamaWarmupJob < ApplicationJob
  queue_as :default

  def perform
    LlamaWarmupService.call
  end
end
