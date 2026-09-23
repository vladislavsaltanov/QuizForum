module ModerationTestHelper
  # Temporarily replaces the Laya verdict without touching IO.
  def with_verdict(verdict, category = "")
    ModerationClient.define_singleton_method(:check) do |*_, **_|
      ModerationClient::Result.new(verdict, category)
    end
    yield
  ensure
    ModerationClient.singleton_class.remove_method(:check)
  end
end

ActiveSupport.on_load(:action_dispatch_integration_test) do
  include ModerationTestHelper
end
