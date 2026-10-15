require "test_helper"

class AiPackWatchdogJobTest < ActiveSupport::TestCase
  setup do
    @calls = []
    calls = @calls
    @original = AiDailyGenerateJob.method(:perform_now)
    AiDailyGenerateJob.define_singleton_method(:perform_now) { |**kw| calls << kw }
    @old_key = ENV["GEMINI_API_KEY"]
    ENV["GEMINI_API_KEY"] = "test-key"
  end

  teardown do
    AiDailyGenerateJob.define_singleton_method(:perform_now, @original)
    if @old_key.nil?
      ENV.delete("GEMINI_API_KEY")
    else
      ENV["GEMINI_API_KEY"] = @old_key
    end
  end

  test "does nothing before 17:00" do
    travel_to AiQuestions.pack_due_at(AiQuestions.today) - 1.hour do
      AiPackWatchdogJob.perform_now

      assert_empty @calls
    end
  end

  test "generates missing pack after 17:00" do
    travel_to AiQuestions.pack_due_at(AiQuestions.today) + 1.hour do
      AiPackWatchdogJob.perform_now

      assert_equal [ { batch: AiQuestions.today.to_s } ], @calls
    end
  end

  test "does nothing when today's pack exists" do
    travel_to AiQuestions.pack_due_at(AiQuestions.today) + 1.hour do
      Question.create!(title: "Есть", body: "Тело", answer_type: "text",
        deadline: 7.days.from_now, reference_answer: "Ответ",
        author: users(:one), ai_generated: true, ai_batch: AiQuestions.today)

      AiPackWatchdogJob.perform_now

      assert_empty @calls
    end
  end

  test "does nothing without a Gemini key" do
    ENV.delete("GEMINI_API_KEY")
    travel_to AiQuestions.pack_due_at(AiQuestions.today) + 1.hour do
      AiPackWatchdogJob.perform_now

      assert_empty @calls
    end
  end
end
