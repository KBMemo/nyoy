# frozen_string_literal: true

class MemoKnowledgeFormatter
  PREAMBLE = <<~TEXT.squish
    以下はユーザーの質問に関連しそうな徒然メモの抜粋です。回答に必要なら参照してください。
    全文や更新が必要なときは get_memo / update_memo ツールを使えます。
  TEXT

  def initialize(max_chars: Rails.application.config.x.nyoy.memo_rag_max_chars)
    @max_chars = max_chars.to_i.positive? ? max_chars.to_i : 12_000
  end

  def format(chunks)
    return nil if chunks.blank?

    lines = [PREAMBLE]
    chunks.each do |chunk|
      entry = entry_for(chunk)
      candidate = lines.join("\n\n") + "\n\n" + entry
      break if candidate.length > @max_chars && lines.length > 1

      lines << entry
      break if candidate.length >= @max_chars
    end

    text = lines.join("\n\n")
    text.length > @max_chars ? text[0, @max_chars] : text
  end

  private

  def entry_for(chunk)
    if chunk.is_a?(MemoKnowledgeChunkCompressor::CompressedChunk)
      format_compressed(chunk)
    else
      chunk.to_memo_rag_context
    end
  end

  def format_compressed(chunk)
    uid = chunk.metadata["memo_uid"] || chunk.metadata[:memo_uid]
    lines = ["[memo:#{uid}] #{chunk.title}"]
    lines << chunk.body
    lines.join("\n")
  end
end
