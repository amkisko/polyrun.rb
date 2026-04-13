Rails.application.routes.draw do
  # Define your application routes per the DSL in https://guides.rubyonrails.org/routing.html

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check

  # Render dynamic PWA files from app/views/pwa/* (remember to link manifest in application.html.erb)
  # get "manifest" => "rails/pwa#manifest", as: :pwa_manifest
  # get "service-worker" => "rails/pwa#service_worker", as: :pwa_service_worker

  root "home#index"

  namespace :platform do
    root "hub#index"
    get ":vertical", to: "verticals#show", as: :vertical,
      constraints: {vertical: /banking|clinic|library|ledger|blog|forum|assistant|analytics/}
  end

  namespace :api do
    namespace :v1 do
      get "health", to: "health#show"
      get "catalog", to: "catalog#show"
      get "items", to: "items#index"
      get "items/:slug", to: "items#show"
    end
  end

  post "/graphql", to: "graphql#execute"

  namespace :admin do
    root "home#index"
  end

  namespace :store do
    root "home#index"
  end

  namespace :portal do
    root "home#index"
  end
end
