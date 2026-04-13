Capybara.register_driver :playwright do |app|
  Capybara::Playwright::Driver.new(app, browser_type: :chromium, headless: true)
end

Capybara.save_path = "log/capybara"
Capybara.default_max_wait_time = 5
