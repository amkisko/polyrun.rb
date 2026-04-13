require "rails_helper"

RSpec.describe "Multi-Vite frontends", type: :system do
  it "serves admin and store static bundles" do
    visit admin_root_path
    expect(page).to have_css('[data-testid="admin-heading"]')
    expect(page).to have_css('body[data-app="admin"]')

    visit store_root_path
    expect(page).to have_css('[data-testid="store-heading"]')
    expect(page).to have_css('body[data-app="store"]')
  end

  it "isolates named sessions for admin, store, and platform hubs", :multi_session do
    using_session(:admin) do
      visit admin_root_path
      expect(page).to have_css('body[data-app="admin"]')
    end

    using_session(:store) do
      visit store_root_path
      expect(page).to have_css('body[data-app="store"]')
    end

    using_session(:platform) do
      visit platform_root_path
      expect(page).to have_css('[data-testid="platform-heading"]')
    end
  end
end
