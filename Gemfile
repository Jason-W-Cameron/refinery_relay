source "https://rubygems.org"

# Specify your gem's dependencies in refinery_relay.gemspec.
gemspec

# Match the Rails 8-compatible Refinery baseline used by SimonSays. Host apps
# remain responsible for selecting their compatible Refinery source.
gem "decorators", git: "https://github.com/parndt/decorators.git", ref: "8ba6dc68c30b5400ee97c642d57748ecaa94830c"
gem "refinerycms-core", git: "https://github.com/refinery/refinerycms.git", ref: "28c0d7754b60e4e50172e34088f03be504934e46"
gem "refinerycms-pods", path: "../../simonsays2021/vendor/extensions/pods"

gem "puma"

gem "sqlite3"

# Omakase Ruby styling [https://github.com/rails/rubocop-rails-omakase/]
gem "rubocop-rails-omakase", require: false

# Start debugger with binding.b [https://github.com/ruby/debug]
# gem "debug", ">= 1.0.0"
