source "https://rubygems.org"

# Specify your gem's dependencies in refinery_relay.gemspec.
gemspec

# Use the Refinery baseline for development. Consuming applications can
# select their own compatible Refinery source.
gem "decorators", git: "https://github.com/parndt/decorators.git", ref: "8ba6dc68c30b5400ee97c642d57748ecaa94830c"
gem "refinerycms-core", git: "https://github.com/refinery/refinerycms.git", ref: "28c0d7754b60e4e50172e34088f03be504934e46"

gem "puma"
gem "sqlite3", ">= 2.1"
# Older FFI releases cannot load on Ruby 3.4+; Sass's file watcher uses it.
gem "ffi", ">= 1.15"
gem "rubocop-rails-omakase", require: false
