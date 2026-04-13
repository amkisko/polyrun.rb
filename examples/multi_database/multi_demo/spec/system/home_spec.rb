require "rails_helper"

RSpec.describe "Home page", type: :system do
  it "renders welcome copy" do
    visit root_path
    expect(page).to have_css('[data-testid="welcome"]', text: /Capybara/)
  end
end
