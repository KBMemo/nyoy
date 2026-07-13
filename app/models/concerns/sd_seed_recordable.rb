# frozen_string_literal: true

module SdSeedRecordable
  extend ActiveSupport::Concern

  def random_seed?
    seed.nil? || seed.to_i.negative?
  end

  def record_actual_seed!(value)
    return if value.nil?
    return unless random_seed?

    update!(seed: value.to_i)
  end
end
