# Hooks: one cheap prepare per process before the first system example (extend for suite-level asset digests).
# Heavy work belongs in ./script/ci_prepare (Vite builds, Playwright browsers) and Polyrun::Prepare::Assets markers —
# not in before(:each). This hook is the extension point if you add TestEnv asset digests or Playwright version files.
module DemoTestEnv
  module_function

  def before_system_suite
    return if @ready

    @ready = true
  end
end

RSpec.configure do |config|
  config.before(:each, type: :system) do
    DemoTestEnv.before_system_suite
  end
end
