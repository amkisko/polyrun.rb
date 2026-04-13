module Platform
  class VerticalsController < ApplicationController
    def show
      slug = params[:vertical].to_s
      unless Platform::VERTICALS.include?(slug)
        head :not_found
        return
      end

      @vertical = slug
      @label = Platform.label_for(slug)
    end
  end
end
