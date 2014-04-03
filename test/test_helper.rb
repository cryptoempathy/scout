ENV['RACK_ENV'] = 'test'

require 'rubygems'
require 'test/unit'

require 'bundler/setup'
require 'rack/test'

require './scout'
require './test/factories'

require 'rspec/mocks'
require 'timecop'

set :environment, :test

module TestHelper

  module Methods

    # Test::Unit hooks

    def setup
      # FREEZE TIME
      Timecop.freeze

      RSpec::Mocks.setup(self)

      Subscriptions::Manager.stub(:download).and_return("{}")
      Feedbag.stub(:find).and_return([])

      services = YAML.safe_load_file File.join(File.dirname(__FILE__), "fixtures/services.yml")
      Environment.stub(:services).and_return(services)
    end

    def verify
      RSpec::Mocks.verify
    end

    def teardown
      Mongoid.models.each &:delete_all
      RSpec::Mocks.teardown
      Timecop.return
    end


    # factory for interests

    def search_interest!(user, search_type = "all", interest_in = "foia", query_type = "simple", filters = {}, attributes = {})
      interest = Interest.for_search user, search_type, interest_in, query_type, filters
      interest.attributes = attributes

      # will be harmless if fixture doesn't exist
      interest.ensure_subscriptions
      interest.subscriptions.each do |subscription|
        [:initialize, :check, :search].each do |function|
          path = fixture_path subscription, function
          if File.exists?("test/fixtures/#{path}.json")
            mock_search subscription, function
          end
        end
      end

      interest.save!
      interest
    end

    # mock helpers for faking remote content

    # runs a block with the cache guaranteed to be on,
    # then restores it to whatever it was beforehand
    def with_cache_on
      if block_given?
        no_cache = Environment.config['no_cache']
        Environment.config['no_cache'] = false
        yield
        Environment.config['no_cache'] = no_cache
      end
    end

    def mock_response(url, fixture)
      if fixture["."]
        file = "test/fixtures/#{fixture}"
      else
        file = "test/fixtures/#{fixture}.json"
      end

      if File.exists?(file)
        content = File.read file

        # handle basic fetch, or with adapter passed in
        Subscriptions::Manager.stub(:download).with(url).and_return content
        Subscriptions::Manager.stub(:download).with(url, anything).and_return content
      else
        Subscriptions::Manager.stub(:download).and_raise Errno::ECONNREFUSED.new
      end
    end

    def fixture_path(subscription, function = :search)
      "#{subscription.subscription_type}/#{subscription.interest_in}/#{function}"
    end

    def mock_search(subscription, function = :search, options = {})
      fixture = fixture_path subscription, function
      url = subscription.adapter.url_for subscription, function, options
      mock_response url, fixture
    end

    def cache_search(subscription, function = :search)
      fixture = fixture_path subscription, function
      file = "test/fixtures/#{fixture}.json"
      content = File.read file

      url = subscription.adapter.url_for subscription, function, {page: 1, per_page: 20}
      Subscriptions::Manager.cache! url, :search, subscription.subscription_type, content
    end

    def mock_item(item_id, item_type)
      subscription_type = item_types[item_type]['adapter']
      fixture = "#{subscription_type}/item/#{item_id}"
      url = Subscription.adapter_for(subscription_type).url_for_detail item_id
      mock_response url, fixture
    end

    def cache_item_direct(item_id, item_type)
      subscription_type = item_types[item_type]['adapter']
      adapter = Subscription.adapter_for subscription_type

      fixture = "#{subscription_type}/item/#{item_id}"
      file = "test/fixtures/#{fixture}.json"
      content = File.read file
      response = ::Oj.load content, mode: :compat

      seen_item = adapter.item_detail_for response
      seen_item.item_type = item_type

      Item.from_seen! seen_item
    end

    def cache_item(item_id, item_type)
      subscription_type = item_types[item_type]['adapter']

      fixture = "#{subscription_type}/item/#{item_id}"
      file = "test/fixtures/#{fixture}.json"
      content = File.read file

      url = Subscription.adapter_for(subscription_type).url_for_detail item_id

      Subscriptions::Manager.cache! url, :find, subscription_type, content
    end

    # helper helpers
    class Anonymous; extend Helpers::Routing; end
    def routing; Anonymous; end


    # Sinatra helpers

    def app
      Sinatra::Application
    end

    def login(user)
      {"rack.session" => {'user_id' => user.id.to_s}}
    end

    def session(hash = {})
      {"rack.session" => hash}
    end

    # custom helpers

    def redirect_path
      if last_response.headers['Location']
        last_response.headers['Location'].sub(/http:\/\/example.org/, '')
      else
        nil
      end
    end

    def assert_response(status, message = nil)
      assert_equal status, last_response.status, (message || last_response.body)
    end

    def assert_redirect(path)
      assert_response 302
      assert_equal path, redirect_path
    end

    def json_response
      JSON.parse last_response.body
    end

  end
end