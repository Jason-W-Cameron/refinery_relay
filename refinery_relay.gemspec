require_relative "lib/refinery_relay/version"

Gem::Specification.new do |spec|
  spec.name        = "refinery_relay"
  spec.version     = RefineryRelay::VERSION
  spec.authors     = [ "Jason-W-Cameron" ]
  spec.email       = [ "jason@niimble.io" ]
  spec.homepage    = "https://niimble.io"
  spec.summary     = "Refinery CMS integration for Niimble Relay."
  spec.description = "A Rails engine that integrates Refinery CMS sites with Niimble Relay chat."
  spec.license     = "MIT"

  spec.metadata["homepage_uri"] = spec.homepage

  spec.files = Dir.chdir(File.expand_path(__dir__)) do
    Dir["{app,config,db,lib}/**/*", "MIT-LICENSE", "Rakefile", "README.md"]
  end

  # This branch supports the legacy Refinery/SIT_V4 stack. Keep these bounds
  # narrow so Bundler cannot accidentally upgrade the host application.
  spec.required_ruby_version = ">= 2.5", "< 2.6"

  spec.add_dependency "rails", ">= 5.1.7", "< 5.2"
  spec.add_dependency "refinerycms-core", ">= 4.0.3", "< 4.1"
  spec.add_dependency "refinerycms-pods", "~> 1.0"
  spec.add_dependency "redis", "~> 4.8"
  spec.add_dependency "nokogiri", ">= 1.8", "< 1.14"

  spec.add_development_dependency "capybara", "~> 3.24"
  spec.add_development_dependency "selenium-webdriver", "~> 3.142.3"
  spec.add_development_dependency "ffi", "~> 1.11.1"
end
