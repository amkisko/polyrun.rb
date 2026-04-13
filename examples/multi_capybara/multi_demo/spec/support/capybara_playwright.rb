# Playwright driver (browser, headless, CLI path, timeout).
# System specs skip when PlaywrightEnv.cli_available? is false (rails_helper).
# Named sessions: using_session(:admin) / :store / :platform (see capybara_sessions.rb, multi_frontends_spec).
Capybara.save_path = ENV.fetch("CAPYBARA_ARTIFACTS", "log/capybara")
Capybara.default_max_wait_time = ENV.fetch("CAPYBARA_MAX_WAIT", "10").to_i

headless = ENV["HEADFUL"].blank? || ENV["CI"].present?

Capybara.register_driver :playwright do |app|
  opts = {
    app: app,
    browser_type: ENV.fetch("BROWSER", "chromium").to_sym,
    headless: headless,
    timeout: Capybara.default_max_wait_time
  }
  path = ENV["PLAYWRIGHT_CLI_EXECUTABLE_PATH"].to_s.strip
  opts[:playwright_cli_executable_path] = path.empty? ? "npx playwright" : path
  Capybara::Playwright::Driver.new(**opts)
end

Capybara.javascript_driver = :playwright
