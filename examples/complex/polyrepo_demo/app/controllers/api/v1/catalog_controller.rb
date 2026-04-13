module Api
  module V1
    # Single JSON snapshot of catalog + platform verticals — same data as GraphQL + gRPC ListItems.
    class CatalogController < BaseController
      def show
        render json: {
          service: "polyrepo-complex-demo",
          items: Catalog.items,
          verticals: Platform::VERTICALS.map { |s| {slug: s, label: Platform.label_for(s)} }
        }
      end
    end
  end
end
