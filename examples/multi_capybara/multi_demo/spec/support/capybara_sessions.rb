# Named Capybara sessions for parallel "apps" in one Rails process (same host/port).
# Playwright-backed system specs can use using_session(:admin) / :store / :platform (substrate-style multi-Capybara).
#
# Example:
#   using_session(:admin) { visit admin_root_path }
#   using_session(:store) { visit store_root_path }
#   using_session(:platform) { visit platform_root_path }

RSpec.configure do |config|
  config.before(:each, :multi_session) do
    unless PlaywrightEnv.cli_available?
      skip "using_session requires Playwright: #{PlaywrightEnv.hint}"
    end
  end
end
