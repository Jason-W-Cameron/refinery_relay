RefineryRelay::Engine.routes.draw do
  namespace :api do
    namespace :relay do
      get "chat/availability", to: "chats#availability"
      post "chat", to: "chats#create"
    end
  end
end
