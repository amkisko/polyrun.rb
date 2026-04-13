module Api
  module V1
    class HealthController < BaseController
      def show
        render json: {
          status: "ok",
          service: "polyrepo-complex-demo",
          api: "v1",
          protocols: %w[rest graphql grpc],
          verticals: Platform::VERTICALS.map { |s| {slug: s, label: Platform.label_for(s)} }
        }
      end
    end
  end
end
