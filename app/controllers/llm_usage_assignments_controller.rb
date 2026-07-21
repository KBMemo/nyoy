# frozen_string_literal: true

class LlmUsageAssignmentsController < ApplicationController
  before_action :set_assignment, only: :update

  def index
    LlmUsageAssignmentSeeds.seed!
    load_index
  end

  def update
    if @assignment.update(llm_usage_assignment_params)
      redirect_to llm_usage_assignments_path(anchor: helpers.dom_id(@assignment)), notice: "#{@assignment.definition.label}を更新しました。"
    else
      load_index
      flash.now[:alert] = @assignment.errors.full_messages.to_sentence
      render :index, status: :unprocessable_entity
    end
  end

  private

  def set_assignment
    @assignment = LlmUsageAssignment.find(params[:id])
  end

  def load_index
    @assignments = LlmUsageCatalog.all.filter_map do |definition|
      if @assignment&.usage_key == definition.key
        @assignment
      else
        LlmUsageAssignment.includes(:model, :fallback_model, :llm_sampling_preset).find_by(usage_key: definition.key)
      end
    end
    @model_options = @assignments.to_h do |assignment|
      [ assignment.id, model_options_for(assignment) ]
    end
    @missing_capabilities = @assignments.to_h do |assignment|
      [ assignment.id, assignment.definition.capabilities - LlmModelCapabilities.for(assignment.model) ]
    end
    @sampling_presets = LlmSamplingPreset.enabled.ordered
  end

  def model_options_for(assignment)
    required = assignment.definition.capabilities
    candidates = Model.all.select do |model|
      (required - LlmModelCapabilities.for(model)).empty? && available_connection_for(model)
    end
    candidates |= [ assignment.model, assignment.fallback_model ].compact
    candidates.sort_by { |model| [ model.name.to_s.downcase, model.model_id.to_s ] }.map do |model|
      connection = model.service_connection
      suffix = connection&.enabled? ? connection.name : "接続利用不可"
      [ "#{model.name.presence || model.model_id} - #{suffix}", model.id ]
    end
  end

  def available_connection_for(model)
    connection = model.service_connection
    connection&.enabled?
  end

  def llm_usage_assignment_params
    params.require(:llm_usage_assignment).permit(
      :model_id,
      :fallback_model_id,
      :llm_sampling_preset_id,
      :enabled
    )
  end
end
