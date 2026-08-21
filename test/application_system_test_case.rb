# frozen_string_literal: true

require "test_helper"
require "capybara/rails"
require "selenium-webdriver"

Selenium::WebDriver.logger.level = :warn
Selenium::WebDriver::Chrome::Service.driver_path = ENV["CHROMEDRIVER_PATH"] if ENV["CHROMEDRIVER_PATH"].present?

class ApplicationSystemTestCase < ActionDispatch::SystemTestCase
  driven_by :selenium, using: :headless_chrome, screen_size: [ 1400, 1200 ]
end
