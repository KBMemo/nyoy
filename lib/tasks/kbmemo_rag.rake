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

    desc "Show memo RAG webhook configuration, event counts, and recent failures"
    task webhook_status: :environment do
      stats = MemoRagWebhookStatus.current(limit: ENV.fetch("LIMIT", MemoRagWebhookStatus::DEFAULT_LIMIT))

      puts "Memo RAG webhook"
      puts "-" * 48
      puts format("%-26s %s", "Enabled", stats.enabled ? "yes" : "no")
      puts format("%-26s %s", "Secret configured", stats.secret_configured ? "yes" : "no")
      puts format("%-26s %d", "Events (total)", stats.total_events)
      puts format("%-26s %s", "Last received", KbmemoRagTasks.format_time(stats.last_received_at))
      puts format("%-26s %s", "Last processed", KbmemoRagTasks.format_time(stats.last_processed_at))

      puts "\nBy status:"
      stats.status_counts.each do |status, count|
        puts format("  %-24s %6d", status, count)
      end

      KbmemoRagTasks.print_webhook_events("Stuck pending/processing", stats.stuck_events)
      KbmemoRagTasks.print_webhook_events("Recent failures", stats.failed_events)
      KbmemoRagTasks.print_webhook_events("Recent events", stats.recent_events)
    end
  end
end

module KbmemoRagTasks
  module_function

  def format_time(value)
    value&.iso8601 || "-"
  end

  def print_webhook_events(title, events)
    puts "\n#{title}:"
    if events.empty?
      puts "  none"
      return
    end

    events.each do |event|
      suffix = event.error_message.present? ? " error=#{event.error_message.inspect}" : ""
      puts "  #{event.event_type} #{event.status} uid=#{event.memo_uid} event_id=#{event.event_id} processed=#{format_time(event.processed_at)}#{suffix}"
    end
  end
end
