# frozen_string_literal: true

namespace :kbmemo do
  namespace :rag do
    desc "徒然メモを export してメモ RAG チャンクを同期する"
    task ingest: :environment do
      updated_since = ENV["UPDATED_SINCE"]
      parsed = updated_since.present? ? Time.zone.parse(updated_since) : nil
      MemoKnowledgeIngestJob.perform_now(updated_since: parsed)
      puts "Memo RAG ingest finished."
    end
  end
end
