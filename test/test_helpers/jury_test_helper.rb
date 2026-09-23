module JuryTestHelper
  extend ActiveSupport::Concern

  ORIGINAL_NEW = JuryClient.method(:new)

  included do
    setup { stub_jury_review }
    teardown { unstub_jury }
  end

  # Temporarily replaces the jury outcome without touching IO.
  def with_jury(result)
    stub_jury(result)
    yield
  ensure
    stub_jury_review
  end

  private
    def stub_jury(result)
      fake = Object.new
      fake.define_singleton_method(:grade) { |*_, **_| result }
      JuryClient.define_singleton_method(:new) { |*_| fake }
    end

    # Default is an unconfident review: performed jobs never auto-set verdicts silently.
    def stub_jury_review
      stub_jury(JuryClient::Result.new("partial", 0.5, true, [], []))
    end

    def unstub_jury
      JuryClient.define_singleton_method(:new, ORIGINAL_NEW)
    end
end

ActiveSupport.on_load(:action_dispatch_integration_test) do
  include JuryTestHelper
end

ActiveSupport.on_load(:active_support_test_case) do
  include JuryTestHelper
end
