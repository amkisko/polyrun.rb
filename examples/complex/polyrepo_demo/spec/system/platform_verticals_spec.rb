require "rails_helper"

RSpec.describe "Platform verticals", type: :system do
  it "shows the hub and opens a business vertical" do
    visit platform_root_path
    expect(page).to have_css('[data-testid="platform-heading"]', text: /Super-platform hub/i)
    find('[data-testid="vertical-link-banking"]').click
    expect(page).to have_css('[data-testid="vertical-title"]', text: "Retail Banking")
    expect(page).to have_css('[data-testid="vertical-banking"]')
  end
end
