require "test_helper"

class GeminiClientTest < ActiveSupport::TestCase
  setup do
    @primary = GeminiClient.model
    @fallback = GeminiClient.fallback_model
  end

  test "primary model success returns the pack without touching fallback" do
    client = stubbed_client({ @primary => pack_payload })
    models = client.used_models

    assert_equal 9, client.generate_pack.size
    assert_equal [ @primary ], models
  end

  test "primary failure falls back to the spare model" do
    client = stubbed_client({ @primary => nil, @fallback => pack_payload })

    assert_equal 9, client.generate_pack.size
    assert_equal [ @primary ] * 3 + [ @fallback ], client.used_models
  end

  test "transient primary failure retries the same model before fallback" do
    calls = Hash.new(0)
    payload = pack_payload
    client = GeminiClient.new
    client.define_singleton_method(:request) do |_, model:|
      calls[model] += 1
      calls[model] < 3 ? nil : payload
    end
    client.define_singleton_method(:sleep) { |*| }

    assert_equal 9, client.generate_pack.size
    assert_equal 3, calls[@primary]
    assert_equal 0, calls[@fallback]
  end

  test "both models failing returns nil" do
    client = stubbed_client({})

    assert_nil client.generate_pack
  end

  test "off-shape payload counts as failure and tries fallback" do
    client = stubbed_client({ @primary => { "candidates" => [] }, @fallback => pack_payload })

    assert_equal 9, client.generate_pack.size
  end

  test "prompt lists recent titles to avoid" do
    prompt = GeminiClient.new.send(:prompt, Question::DIFFICULTIES, %w[Старый1 Старый2])

    assert_match(/Не повторяй эти темы/, prompt)
    assert_match(/- Старый1/, prompt)
  end

  test "request returns nil on an http error" do
    fake = Object.new
    fake.define_singleton_method(:use_ssl=) { |*| }
    fake.define_singleton_method(:open_timeout=) { |*| }
    fake.define_singleton_method(:read_timeout=) { |*| }
    fake.define_singleton_method(:request) do |_req|
      Net::HTTPNotFound.new("1.1", "404", "Not Found").tap { |res| res.instance_variable_set(:@read, true) }
    end
    Net::HTTP.define_singleton_method(:new) { |*_| fake }

    assert_nil GeminiClient.new.send(:request, "prompt", model: @primary)
  ensure
    Net::HTTP.singleton_class.remove_method(:new)
  end

  test "request parses a successful response body" do
    body = JSON.generate(candidates: [ { content: { parts: [ { text: "[]" } ] } } ])
    fake = Object.new
    fake.define_singleton_method(:use_ssl=) { |*| }
    fake.define_singleton_method(:open_timeout=) { |*| }
    fake.define_singleton_method(:read_timeout=) { |*| }
    fake.define_singleton_method(:request) do |_req|
      Net::HTTPOK.new("1.1", "200", "OK").tap do |res|
        res.instance_variable_set(:@body, body)
        res.instance_variable_set(:@read, true)
      end
    end
    Net::HTTP.define_singleton_method(:new) { |*_| fake }

    payload = GeminiClient.new.send(:request, "prompt", model: @primary)

    assert payload.is_a?(Hash)
    assert_equal "[]", payload.dig("candidates", 0, "content", "parts", 0, "text")
  ensure
    Net::HTTP.singleton_class.remove_method(:new)
  end

  test "extract returns nil for a json array body" do
    payload = { "candidates" => [ { "content" => { "parts" => [ { "text" => JSON.generate([ 1, 2 ]) } ] } } ] }

    assert_nil GeminiClient.new.send(:extract, payload, model: @primary)
  end

  private
    def pack_payload
      { "candidates" => [ { "content" => { "parts" => [ { "text" => JSON.generate(questions: pack_items) } ] } } ] }
    end

    def pack_items
      levels = %w[легкое среднее сложное]
      Array.new(9) do |i|
        { "title" => "Сгенерённый #{i}", "body" => "Условие #{i}", "answer_type" => "text",
          "reference_answer" => "Ответ #{i}", "explanation" => "Разбор #{i}",
          "difficulty" => levels[i / 3], "topics" => [ "тема#{i}" ] }
      end
    end

    # Client with the HTTP layer swapped for a canned payload map; records models tried.
    def stubbed_client(payloads)
      client = GeminiClient.new
      client.define_singleton_method(:sleep) { |*| }
      client.instance_variable_set(:@payloads, payloads)
      client.instance_variable_set(:@used_models, [])
      def client.used_models
        @used_models
      end
      def client.request(_prompt, model:)
        @used_models << model
        @payloads[model]
      end
      client
    end
end
