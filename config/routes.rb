Rails.application.routes.draw do
  # Rotas para grupos
  resources :groups, only: [ :index, :show, :create, :update, :destroy ] do
    resources :expenses, only: [ :index, :show, :create, :update, :destroy ] do
      post "settle", on: :member
    end
    resources :payments, only: [ :index, :show, :create, :update, :destroy ]
    resources :group_memberships, only: [ :create, :destroy ]
    get "balances_and_settlements", on: :member
  end

  # Rotas para usuários
  resources :users, only: [ :index, :create, :show ]

  # Rotas para autenticação (sessões)
  post "/login", to: "sessions#create"
  delete "/logout", to: "sessions#destroy"
  get "/logged_in", to: "sessions#logged_in" # Para verificar status de login no frontend

  # Rota de teste da API
  get "greetings/hello"

  # Rotas do frontend React
  get "frontend/index"
  get "*path", to: "frontend#index", constraints: ->(req) do
    !req.xhr? && req.format.html?
  end
  root "frontend#index"

  # Health check do Rails
  get "up" => "rails/health#show", as: :rails_health_check
end
