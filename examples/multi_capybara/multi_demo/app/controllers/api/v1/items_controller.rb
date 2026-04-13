module Api
  module V1
    class ItemsController < BaseController
      def index
        render json: { items: Catalog.items }
      end

      def show
        item = Catalog.find_by_slug(params[:slug])
        if item
          render json: { item: item }
        else
          render json: { error: "not_found" }, status: :not_found
        end
      end
    end
  end
end
