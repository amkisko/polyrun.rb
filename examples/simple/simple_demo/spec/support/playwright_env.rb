# Detect Playwright CLI (npx, local node_modules, or PLAYWRIGHT_CLI_EXECUTABLE_PATH).
# System specs use :playwright when the CLI is available; otherwise they skip with a hint.
require "open3"

module PlaywrightEnv
  module_function

  def cli_available?
    return @cli if defined?(@cli)

    @cli = detect
  end

  def hint
    "Playwright CLI not found. npm install playwright && npx playwright install chromium"
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
