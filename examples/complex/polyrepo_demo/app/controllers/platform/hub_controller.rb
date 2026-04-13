module Platform
  class HubController < ApplicationController
    def index
      @verticals = Platform::VERTICALS
    end
  end
end
