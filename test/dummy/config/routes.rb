Rails.application.routes.draw do
  root to: "relay_test#show", defaults: { pod_id: 0 }
  get "/relay_test/:pod_id", to: "relay_test#show", as: :relay_test
  mount ActionCable.server => "/cable"

end
