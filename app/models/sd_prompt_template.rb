# frozen_string_literal: true

# Parameter-tab direct generation: model/family-specific prompt generation template
# (system prompt body). JSON contract and resolver live in DirectPromptGenerator (Phase 2).
class SdPromptTemplate < ApplicationRecord
  FAMILIES = SdModelProfile::FAMILIES
  FAMILY_LABELS = SdModelProfile::FAMILY_LABELS

  belongs_to :sd_model_profile, optional: true

  validates :name, :body, presence: true
  validates :family, inclusion: { in: FAMILIES }, allow_nil: true
  validate :scope_target_exclusive
  validate :family_matches_model_profile

  scope :enabled, -> { where(enabled: true) }
  scope :ordered, -> { order(sort_order: :asc, name: :asc) }
  scope :global, -> { where(family: nil, sd_model_profile_id: nil) }
  scope :for_family, ->(family) { where(family: family, sd_model_profile_id: nil) }
  scope :for_model, ->(profile) { where(sd_model_profile_id: profile) }

  def global?
    family.blank? && sd_model_profile_id.blank?
  end

  def family_label
    return if family.blank?

    FAMILY_LABELS.fetch(family, family)
  end

  def scope_label
    if sd_model_profile_id.present?
      "モデル専用"
    elsif family.present?
      "ファミリ既定（#{family_label}）"
    else
      "グローバル既定"
    end
  end

  private

  def scope_target_exclusive
    return unless sd_model_profile_id.present? && family.present?

    errors.add(:base, "ファミリ既定とモデル専用は同時に指定できません")
  end

  def family_matches_model_profile
    return if sd_model_profile.blank? || family.blank?

    return if sd_model_profile.family == family

    errors.add(:family, "は選択したモデルプロファイルのファミリと一致している必要があります")
  end
end
