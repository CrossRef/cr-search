ENV['RACK_ENV'] = 'test'

require 'sinatra'
require 'rspec'
require 'rack/test'
require 'webmock/rspec'
require 'vcr'
require 'capybara/rspec'
require 'capybara/poltergeist'
require 'capybara-screenshot/rspec'
require 'tilt/haml'

require File.join(File.dirname(__FILE__), '..', 'app.rb')
app_root = File.dirname(settings.app_file)
# require support files, and files in lib folder
#Dir[File.join(File.dirname(__FILE__), 'support/**/*.rb')].each { |f| require f }
Dir[File.join(app_root, '/lib/**/*.rb')].each { |f| require f }

# setup test environment
set :environment, :test
set :run, false
set :raise_errors, true
set :logging, false
set :dump_errors, false
set :show_exceptions, false

def app
  Sinatra::Application
end

Capybara.app = app

RSpec.configure do |config|
  config.include Rack::Test::Methods
  config.include Capybara::DSL
  config.order = :random
end

Capybara.register_driver :poltergeist do |app|
  Capybara::Poltergeist::Driver.new(app, {
    timeout: 60,
    inspector: true,
    debug: false,
    window_size: [1024, 768]
  })
end

Capybara.javascript_driver = :poltergeist
Capybara.default_selector = :css
Capybara::Screenshot.prune_strategy = :keep_last_run

Capybara.configure do |config|
  config.match = :prefer_exact
  config.ignore_hidden_elements = true
end


VCR.configure do |c|
  c.cassette_library_dir = 'spec/fixtures/vcr_cassettes'
  c.hook_into :webmock
  c.allow_http_connections_when_no_cassette = true
  c.filter_sensitive_data('<Authorization>') { ENV['CROSSREF_API_TOKEN'] }
  c.configure_rspec_metadata!
end

def capture_stdout(&block)
  stdout, string = $stdout, StringIO.new
  $stdout = string

  yield

  string.tap(&:rewind).read
ensure
  $stdout = stdout
end
