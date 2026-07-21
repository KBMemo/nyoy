class Model < ApplicationRecord
  acts_as_model

  belongs_to :service_connection, optional: true
  has_many :llm_usage_assignments, dependent: :restrict_with_error
  has_many :fallback_llm_usage_assignments,
           class_name: "LlmUsageAssignment",
           foreign_key: :fallback_model_id,
           dependent: :restrict_with_error,
           inverse_of: :fallback_model

  def resolved_service_connection
    service_connection || ServiceConnection.resolve(metadata.to_h["connection_key"])
  end
end
