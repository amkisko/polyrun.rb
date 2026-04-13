# Detect Playwright CLI (npx, local node_modules, or PLAYWRIGHT_CLI_EXECUTABLE_PATH).
# Examples always use the Playwright driver for system specs when the CLI is available — no SKIP_PLAYWRIGHT env.
require "open3"

module PlaywrightEnv
  module_function

  def cli_available?
    return @cli if defined?(@cli)

    @cli = detect
  end

  def hint
    "Install Playwright CLI, then browsers: npm install playwright && npx playwright install chromium. " \
      "Optional: PLAYWRIGHT_CLI_EXECUTABLE_PATH=/path/to/playwright"
  end

  def detect
    if (p = ENV["PLAYWRIGHT_CLI_EXECUTABLE_PATH"].to_s.strip) && !p.empty?
      _out, st = Open3.capture2e(p, "--version")
      return true if st.success?
    end
    _out, st = Open3.capture2e("npx", "playwright", "--version")
    return true if st.success?

    bin = Rails.root.join("node_modules/.bin/playwright")
    return false unless bin.file?

    _out, st = Open3.capture2e(bin.to_s, "--version")
    st.success?
  rescue Errno::ENOENT
    false
  end
end
