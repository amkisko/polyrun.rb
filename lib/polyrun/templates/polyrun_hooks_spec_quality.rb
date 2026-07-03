# Optional Polyrun hooks — copy to config/polyrun_hooks.rb and reference from polyrun.yml:
#   hooks:
#     ruby_file: config/polyrun_hooks.rb
#
# Worker-phase hooks run in each parallel test child (around bundle exec rspec).

before(:each) do |env|
  next unless env["POLYRUN_HOOK_ORCHESTRATOR"] == "0"
  next unless defined?(Polyrun::SpecQuality) && Polyrun::SpecQuality.enabled?

  Polyrun::SpecQuality::RspecHook.ensure_started!
end
