# frozen_string_literal: true

module StylePlanConnectable
  extend ActiveSupport::Concern

  included do
    before_validation :assign_default_style_plan_connection_key
    validate :style_plan_connection_key_must_be_available
  end

  def style_plan_generator(flow:)
    StylePlanGenerator.new(flow: flow, connection_key: style_plan_connection_key)
  end

  def style_plan_connection_label
    StylePlanModelCatalog.label_for(style_plan_connection_key)
  end

  private

  def assign_default_style_plan_connection_key
    return if style_plan_connection_key.present?

    self.style_plan_connection_key = StylePlanModelCatalog.default_connection_key
  end

  def style_plan_connection_key_must_be_available
    return if style_plan_connection_key.blank?

    keys = StylePlanModelCatalog.connection_keys
    return if keys.include?(style_plan_connection_key)

    errors.add(:style_plan_connection_key, "は有効な接続を選んでください")
  end
end
