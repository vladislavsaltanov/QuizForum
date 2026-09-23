module ModerationTestHelper
  extend ActiveSupport::Concern

  included do
    setup { stub_moderation_pass }
    teardown { unstub_moderation }
  end

  # Temporarily replaces the Laya verdict without touching IO.
  def with_verdict(verdict, category = "")
    stub_moderation(ModerationClient::Result.new(verdict, category))
    yield
  ensure
    stub_moderation_pass
  end

  private
    def stub_moderation(result)
      ModerationClient.define_singleton_method(:check) { |*_, **_| result }
    end

    def stub_moderation_pass
      stub_moderation(ModerationClient::Result.new(:pass, ""))
    end

    def unstub_moderation
      ModerationClient.singleton_class.remove_method(:check)
    rescue NameError
      nil
    end
end

ActiveSupport.on_load(:action_dispatch_integration_test) do
  include ModerationTestHelper
end
