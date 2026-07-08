# frozen_string_literal: true

# One-off production runner: reflect the "model family drives default_params"
# change on existing sd_model_profiles.
#
# Background: generation params are now derived from
# SdModelProfile::FAMILY_DEFAULT_PARAMS (keyed by family). A profile's own
# default_params is only meant to hold *deviations* from the family baseline.
# Existing rows still store a full copy of the old baseline in default_params,
# which shadows the family defaults. This clears those copies so family becomes
# authoritative, while KEEPING any genuinely customised params untouched.
#
# Safety:
#   - Idempotent. Re-running is a no-op once cleared.
#   - Only clears default_params that exactly equal the family baseline.
#     Profiles whose params differ (admin customised) are reported and kept.
#   - Touches ONLY sd_model_profiles.default_params. Does not change
#     name/switch_key/enabled/sort_order, and does not run the full db:seed
#     (so service_connections / prompt_styles / render_presets / chat models /
#     RAG chunks are left alone).
#
# Usage:
#   Preview (no writes):
#     DRY_RUN=1 bin/rails runner script/reflect_family_default_params.rb
#   Apply:
#     bin/rails runner script/reflect_family_default_params.rb
#
# Production (kamal) example:
#   bin/kamal app exec 'bin/rails runner script/reflect_family_default_params.rb'

dry_run = ENV["DRY_RUN"].to_s == "1"

def normalize(params)
  # Compare via JSON round-trip so integer/float/key-type differences between
  # the jsonb column and the Ruby constant do not cause false mismatches.
  JSON.parse(JSON.generate(params.to_h))
end

puts "== Reflect family default_params (#{dry_run ? 'DRY RUN' : 'APPLY'}) =="
puts "families: #{SdModelProfile::FAMILIES.join(', ')}"
puts

cleared = 0
kept_custom = 0
already = 0
unknown_family = 0

SdModelProfile.order(:sort_order, :name).find_each do |model|
  baseline = model.family_default_params
  stored = model.default_params.to_h

  if !SdModelProfile::FAMILY_DEFAULT_PARAMS.key?(model.family)
    unknown_family += 1
    puts "  [warn]  #{model.key} family=#{model.family.inspect} has no FAMILY_DEFAULT_PARAMS entry; leaving default_params as-is"
    next
  end

  if stored.blank?
    already += 1
    puts "  [ok]    #{model.key} (#{model.family}) already family-driven"
    next
  end

  if normalize(stored) == normalize(baseline)
    if dry_run
      puts "  [clear?] #{model.key} (#{model.family}) would clear default_params (matches family baseline)"
    else
      model.update!(default_params: {})
      puts "  [clear] #{model.key} (#{model.family}) default_params -> {} (matched family baseline)"
    end
    cleared += 1
  else
    kept_custom += 1
    puts "  [keep]  #{model.key} (#{model.family}) custom default_params kept"
    puts "          stored:   #{stored.inspect}"
    puts "          baseline: #{baseline.inspect}"
  end
end

puts
puts "Resolved params (effective after this run):"
SdModelProfile.order(:sort_order, :name).find_each do |model|
  puts "  #{model.key} family=#{model.family} resolved=#{model.resolved_default_params.inspect}"
end

puts
puts "summary: cleared=#{cleared} kept_custom=#{kept_custom} already_family_driven=#{already} unknown_family=#{unknown_family}#{' (dry run: nothing written)' if dry_run}"
