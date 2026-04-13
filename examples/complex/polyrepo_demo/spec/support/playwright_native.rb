# Optional: use playwright-ruby-client alongside Capybara (null driver pattern).
# See https://playwright-ruby-client.vercel.app/docs/article/guides/rails_integration_with_null_driver
#
# Example (tag a spec with :playwright_native):
#   it "clicks via Playwright API", :playwright_native do
#     page = Playwright.create(playwright_cli_executable_path: ENV.fetch("PLAYWRIGHT_CLI_EXECUTABLE_PATH", "npx"))
#     # ...
#   end
