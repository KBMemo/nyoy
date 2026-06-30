# frozen_string_literal: true

class SdPromptTokensController < ApplicationController
  def create
    text = params[:text].to_s
    count = SdPromptTokenizer.count(text)

    render json: {
      count: count,
      label: SdPromptTokenizer.label(text),
      limit: SdPromptTokenizer::CLIP_TOKEN_LIMIT,
      over_limit: SdPromptTokenizer.over_limit?(text)
    }
  end
end
