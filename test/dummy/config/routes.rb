Rails.application.routes.draw do
  root to: "relay_test#show", defaults: { pod_id: 0 }
  get "/relay_test/:pod_id", to: "relay_test#show", as: :relay_test
  mount ActionCable.server => "/cable"

  get "/refinery_relay/api/relay/chat/availability",
      to: "refinery_relay/api/relay/chats#availability"
  post "/refinery_relay/api/relay/chat",
       to: "refinery_relay/api/relay/chats#create"
end
