# frozen_string_literal: true

namespace :solid_queue do
  desc "Show Solid Queue counts and recent failures"
  task status: :environment do
    SolidQueueTasks.ensure_enabled!

    puts "Solid Queue (#{SolidQueueTasks.queue_database_name})"
    puts "-" * 48
    puts format("%-26s %6d", "Jobs (total)", SolidQueue::Job.count)
    puts format("%-26s %6d", "Ready (pending)", SolidQueue::ReadyExecution.count)
    puts format("%-26s %6d", "Claimed (running)", SolidQueue::ClaimedExecution.count)
    puts format("%-26s %6d", "Scheduled", SolidQueue::ScheduledExecution.count)
    puts format("%-26s %6d", "Blocked", SolidQueue::BlockedExecution.count)
    puts format("%-26s %6d", "Failed", SolidQueue::FailedExecution.count)
    puts format("%-26s %6d", "Finished", SolidQueue::Job.finished.count)
    puts format("%-26s %6d", "Processes", SolidQueue::Process.count)

    ready_by_queue = SolidQueue::ReadyExecution.group(:queue_name).count
    if ready_by_queue.any?
      puts "\nReady by queue:"
      ready_by_queue.sort.each do |queue_name, count|
        puts format("  %-24s %6d", queue_name, count)
      end
    end

    SolidQueueTasks.print_recent_failures
  end

  desc "Delete finished jobs (default: older than clear_finished_jobs_after). Use ALL=1 to delete all finished jobs."
  task clear_finished: :environment do
    SolidQueueTasks.ensure_enabled!

    finished_before = if ENV["ALL"] == "1"
      SolidQueueTasks.require_confirm!("all finished jobs")
      Time.current
    elsif (days = ENV["DAYS"]).present?
      days.to_i.days.ago
    else
      SolidQueue.clear_finished_jobs_after.ago
    end

    before = SolidQueue::Job.clearable(finished_before: finished_before).count
    SolidQueue::Job.clear_finished_in_batches(finished_before: finished_before, sleep_between_batches: 0.3)
    after = SolidQueue::Job.clearable(finished_before: finished_before).count

    puts "Deleted #{before - after} finished job(s) (finished before #{finished_before})."
  end

  desc "Discard failed jobs. Optional JOB_ID=123. Destructive: set CONFIRM=1."
  task clear_failed: :environment do
    SolidQueueTasks.ensure_enabled!

    if (job_id = ENV["JOB_ID"]).present?
      failed = SolidQueue::FailedExecution.find_by!(job_id: job_id)
      failed.discard
      puts "Discarded failed job ##{job_id}."
    else
      SolidQueueTasks.require_confirm!("all failed jobs")
      count = SolidQueue::FailedExecution.count
      SolidQueue::FailedExecution.discard_all_in_batches
      puts "Discarded #{count} failed job(s)."
    end
  end

  desc "Re-enqueue failed jobs. Optional JOB_ID=123."
  task retry_failed: :environment do
    SolidQueueTasks.ensure_enabled!

    if (job_id = ENV["JOB_ID"]).present?
      failed = SolidQueue::FailedExecution.find_by!(job_id: job_id)
      failed.retry
      puts "Re-enqueued failed job ##{job_id}."
    else
      jobs = SolidQueue::Job.failed.to_a
      if jobs.empty?
        puts "No failed jobs."
      else
        SolidQueue::FailedExecution.retry_all(jobs)
        puts "Re-enqueued #{jobs.size} failed job(s)."
      end
    end
  end

  desc "Discard pending ready jobs. Optional QUEUE=image_generation (default: all queues). Destructive: set CONFIRM=1."
  task clear_ready: :environment do
    SolidQueueTasks.ensure_enabled!

    if (queue_name = ENV["QUEUE"]).present?
      SolidQueueTasks.require_confirm!("ready jobs in queue #{queue_name}")
      before = SolidQueue::Queue.find_by_name(queue_name).size
      SolidQueue::Queue.find_by_name(queue_name).clear
      puts "Discarded #{before} ready job(s) from queue #{queue_name}."
    else
      SolidQueueTasks.require_confirm!("ready jobs in all queues")
      total = 0
      SolidQueue::Queue.all.each do |queue|
        size = queue.size
        next if size.zero?

        queue.clear
        total += size
        puts "  #{queue.name}: #{size}"
      end
      puts "Discarded #{total} ready job(s) total."
    end
  end

  desc "Prune worker/dispatcher processes with stale heartbeats"
  task prune_processes: :environment do
    SolidQueueTasks.ensure_enabled!

    before = SolidQueue::Process.prunable.count
    SolidQueue::Process.prune
    puts "Pruned #{before} dead process(es)."
  end
end

module SolidQueueTasks
  module_function

  def ensure_enabled!
    return if Rails.application.config.active_job.queue_adapter == :solid_queue

    abort "Solid Queue is not active (adapter: #{Rails.application.config.active_job.queue_adapter})."
  end

  def queue_database_name
    config = ActiveRecord::Base.configurations.configs_for(env_name: Rails.env, name: "queue")
    config&.database || "primary"
  end

  def require_confirm!(target)
    return if ENV["CONFIRM"] == "1"

    abort "Refusing to delete #{target}. Re-run with CONFIRM=1."
  end

  def print_recent_failures
    failures = SolidQueue::FailedExecution.includes(:job).order(created_at: :desc).limit(10)
    return if failures.empty?

    puts "\nRecent failures:"
    failures.each do |failed|
      job = failed.job
      label = job ? "#{job.class_name} ##{job.id}" : "job ##{failed.job_id}"
      message = failed.message.to_s.truncate(80)
      puts "  #{label}: #{message}"
    end
  end
end
