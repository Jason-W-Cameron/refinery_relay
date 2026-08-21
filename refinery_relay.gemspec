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

  spec.required_ruby_version = ">= 3.2"

  spec.add_dependency "rails", ">= 8.1.3", "< 9"
  spec.add_dependency "refinerycms-core", ">= 4.1", "< 5"
  spec.add_dependency "redis", ">= 5.0", "< 7"

  spec.add_development_dependency "capybara", ">= 3.40", "< 4"
  spec.add_development_dependency "selenium-webdriver", ">= 4.6", "< 5"
end
