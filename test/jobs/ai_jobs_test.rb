require "test_helper"

class AiJobsTest < ActiveJob::TestCase
  test "retention destroys only AI packs past the window" do
    old_pack = ai_question("Старый пак", deadline: 4.days.ago)
    fresh_pack = ai_question("Свежий пак", deadline: 1.hour.ago)
    old_human = Question.create!(title: "Старый людской", body: "Тело", answer_type: "text",
                                 reference_answer: "Ответ", deadline: 30.days.ago,
                                 author: users(:one), tags: [ "среднее" ])

    assert_equal 1, AiRetentionJob.perform_now
    assert_not Question.exists?(old_pack.id)
    assert Question.exists?(fresh_pack.id)
    assert Question.exists?(old_human.id)
  end

  test "retention does nothing with the kill switch off" do
    old = ENV["AI_QUESTIONS_ENABLED"]
    ENV["AI_QUESTIONS_ENABLED"] = "0"
    pack = ai_question("Старый пак", deadline: 30.days.ago)

    assert_equal 0, AiRetentionJob.perform_now
    assert Question.exists?(pack.id)
  ensure
    ENV["AI_QUESTIONS_ENABLED"] = old
  end

  test "generate skips without a Gemini key" do
    old = ENV["GEMINI_API_KEY"]
    ENV.delete("GEMINI_API_KEY")

    AiDailyGenerateJob.perform_now

    assert_equal 0, Question.ai.count
  ensure
    ENV["GEMINI_API_KEY"] = old
  end

  test "generate feeds adapter output through the ingest" do
    ENV["GEMINI_API_KEY"] = "test-key"
    GeminiClient.define_singleton_method(:new) do
      Object.new.tap do |client|
        def client.generate_pack(**_)
          levels = %w[легкое среднее сложное]
          Array.new(9) do |i|
            { title: "Сгенерённый #{i}", body: "Условие #{i}", answer_type: "text",
              reference_answer: "Ответ #{i}", explanation: "Разбор #{i}",
              difficulty: levels[i / 3], topics: [ "тема#{i}" ] }
          end
        end
      end
    end

    AiDailyGenerateJob.perform_now

    assert_equal 9, Question.ai.count
  ensure
    ENV.delete("GEMINI_API_KEY")
    class << GeminiClient
      remove_method :new
    end
  end

  test "generate skips pack creation when the batch already exists" do
    ENV["GEMINI_API_KEY"] = "test-key"
    AiQuestionIngest.call(items: generated_items)
    GeminiClient.define_singleton_method(:new) { raise "adapter must not run" }

    AiDailyGenerateJob.perform_now

    assert_equal 9, Question.ai.count
  ensure
    ENV.delete("GEMINI_API_KEY")
    class << GeminiClient
      remove_method :new
    end
  end

  test "generate creates nothing when the adapter fails" do
    ENV["GEMINI_API_KEY"] = "test-key"
    GeminiClient.define_singleton_method(:new) do
      Object.new.tap do |client|
        def client.generate_pack(**_)
          nil
        end
      end
    end

    AiDailyGenerateJob.perform_now

    assert_equal 0, Question.ai.count
  ensure
    ENV.delete("GEMINI_API_KEY")
    class << GeminiClient
      remove_method :new
    end
  end

  test "generate with force deletes the batch and builds a fresh one" do
    ENV["GEMINI_API_KEY"] = "test-key"
    stale = ai_question("Протухший пак", deadline: 1.hour.from_now)
    GeminiClient.define_singleton_method(:new) do
      Object.new.tap do |client|
        def client.generate_pack(**_)
          levels = %w[легкое среднее сложное]
          Array.new(9) do |i|
            { title: "Свежий #{i}", body: "Условие #{i}", answer_type: "text",
              reference_answer: "Ответ #{i}", explanation: "Разбор #{i}",
              difficulty: levels[i / 3], topics: [ "тема#{i}" ] }
          end
        end
      end
    end

    AiDailyGenerateJob.perform_now(force: true)

    assert_not Question.exists?(stale.id)
    assert_equal 9, Question.ai.count
  ensure
    ENV.delete("GEMINI_API_KEY")
    class << GeminiClient
      remove_method :new
    end
  end

  private
    def generated_items
      levels = %w[легкое среднее сложное]
      Array.new(9) do |i|
        { title: "Сгенерённый #{i}", body: "Условие #{i}", answer_type: "text",
          reference_answer: "Ответ #{i}", explanation: "Разбор #{i}",
          difficulty: levels[i / 3], topics: [ "тема#{i}" ] }
      end
    end
    def ai_question(title, deadline:)
      Question.create!(title: title, body: "Тело", answer_type: "text",
                       reference_answer: "Ответ", deadline:,
                       author: users(:one), tags: [ "ИИ", "среднее" ],
                       ai_generated: true, ai_batch: AiQuestions.today)
    end
end
