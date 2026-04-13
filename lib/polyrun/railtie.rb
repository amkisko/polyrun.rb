module Polyrun
  # Optional Rails integration. Coverage must still be started from +spec_helper.rb+ (before the app loads) via
  # {Polyrun::Coverage::Rails.start!}; this railtie only registers the gem with Rails.
  class Railtie < ::Rails::Railtie
    railtie_name :polyrun
  end
end
