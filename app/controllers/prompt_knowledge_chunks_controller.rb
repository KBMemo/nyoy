# frozen_string_literal: true

class PromptKnowledgeChunksController < ApplicationController
  before_action :set_prompt_knowledge_chunk, only: %i[show edit update destroy]

  def index
    @prompt_knowledge_chunks = PromptKnowledgeChunk.ordered
  end

  def show
  end

  def new
    @prompt_knowledge_chunk = PromptKnowledgeChunk.new(kind: "style")
  end

  def create
    @prompt_knowledge_chunk = PromptKnowledgeChunk.new(prompt_knowledge_chunk_params)

    if @prompt_knowledge_chunk.save
      redirect_to @prompt_knowledge_chunk, notice: "ナレッジを登録しました。"
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
  end

  def update
    if @prompt_knowledge_chunk.update(prompt_knowledge_chunk_params)
      redirect_to @prompt_knowledge_chunk, notice: "ナレッジを更新しました。"
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @prompt_knowledge_chunk.destroy!
    redirect_to prompt_knowledge_chunks_path, notice: "ナレッジを削除しました。"
  end

  def generate_skill
    chunks = PromptKnowledgeChunk.where(id: Array(params[:chunk_ids]).map(&:presence).compact)
    if chunks.empty?
      redirect_to prompt_knowledge_chunks_path, alert: "ナレッジを1件以上選んでください。"
      return
    end

    draft = PromptSkillDraftGenerator.new.call(
      chunks: chunks,
      output_kind: params[:output_kind].presence || "json_plan"
    )
    session[:prompt_skill_draft_token] = PromptSkillDraftStore.write(draft)
    redirect_to new_prompt_skill_path, notice: "スキル草案を生成しました。内容を確認して保存してください。"
  rescue PromptSkillDraftGenerator::Error => e
    redirect_to prompt_knowledge_chunks_path, alert: e.message
  end

  private

  def set_prompt_knowledge_chunk
    @prompt_knowledge_chunk = PromptKnowledgeChunk.find(params[:id])
  end

  def prompt_knowledge_chunk_params
    params.require(:prompt_knowledge_chunk).permit(:title, :body, :kind, metadata: {})
  end
end
