ENV["RAILS_ENV"] ||= "test"
unless ENV["COVERAGE"] == "false"
  require "simplecov"
  SimpleCov.start "rails" do
    enable_coverage :branch
    primary_coverage :branch
    minimum_coverage line: 90, branch: 90
  end
end
require_relative "../config/environment"
require "rails/test_help"
require_relative "test_helpers/session_test_helper"

module ActiveSupport
  class TestCase
    # Run tests in parallel with specified workers
    parallelize(workers: :number_of_processors)

    # Setup all fixtures in test/fixtures/*.yml for all tests in alphabetical order.
    fixtures :all

    # Add more helper methods to be used by all tests here...
  end
end
