require 'capybara/rspec'
require 'selenium-webdriver'

# Configure Capybara
Capybara.default_driver = :rack_test
Capybara.javascript_driver = :selenium_chrome_headless

# Configure Selenium WebDriver for headless Chrome
# Selenium Manager (built into selenium-webdriver 4.6+) automatically downloads and manages ChromeDriver
# It uses the Chrome for Testing repository which supports all Chrome versions including beta/canary
Capybara.register_driver :selenium_chrome_headless do |app|
  options = Selenium::WebDriver::Chrome::Options.new
  options.add_argument('--headless=new')
  options.add_argument('--no-sandbox')
  options.add_argument('--disable-dev-shm-usage')
  options.add_argument('--disable-gpu')
  options.add_argument('--disable-software-rasterizer')
  options.add_argument('--window-size=1920,1080')

  # Selenium Manager handles driver management automatically
  Capybara::Selenium::Driver.new(app, browser: :chrome, options: options)
end

# Configure Selenium WebDriver
RSpec.configure do |config|
  config.before(:each, type: :system) do
    # Default to rack_test unless js: true is specified
    driven_by :rack_test
  end

  config.before(:each, type: :system, js: true) do
    driven_by :selenium_chrome_headless
  end
end
