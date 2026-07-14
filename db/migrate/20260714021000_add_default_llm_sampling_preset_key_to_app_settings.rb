# frozen_string_literal: true

class AddDefaultLlmSamplingPresetKeyToAppSettings < ActiveRecord::Migration[8.0]
  def change
    add_column :app_settings, :default_llm_sampling_preset_key, :string
  end
end
