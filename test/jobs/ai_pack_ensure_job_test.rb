require "test_helper"

class AiPackEnsureJobTest < ActiveSupport::TestCase
  setup do
    @calls = []
    calls = @calls
    @original = AiDailyGenerateJob.method(:perform_now)
    AiDailyGenerateJob.define_singleton_method(:perform_now) { |**kw| calls << kw }
  end

  teardown do
    original = @original
    AiDailyGenerateJob.define_singleton_method(:perform_now, original)
  end

  test "generates missing today pack after its due time" do
    travel_to AiQuestions.pack_due_at(AiQuestions.today) + 1.hour do
      AiPackEnsureJob.perform_now

      assert_equal [ { batch: AiQuestions.today.to_s } ], @calls
    end
  end

  test "boot with live pack does not generate before 17:00 due time" do
    travel_to AiQuestions.pack_due_at(AiQuestions.today) - 1.hour do
      Question.create!(title: "Живая", body: "Тело", answer_type: "text",
        deadline: 7.days.from_now, reference_answer: "Ответ",
        author: users(:one), ai_generated: true, ai_batch: AiQuestions.today - 1)

      AiPackEnsureJob.perform_now

      assert_empty @calls
      assert_equal AiQuestions.today - 1, Question.latest_ai_pack.first.ai_batch
    end
  end

  test "does nothing when today pack exists" do
    travel_to AiQuestions.deadline_for(AiQuestions.today - 1) + 1.hour do
      Question.create!(title: "Есть", body: "Тело", answer_type: "text",
        deadline: 7.days.from_now, reference_answer: "Ответ",
        author: users(:one), ai_generated: true, ai_batch: AiQuestions.today)

      AiPackEnsureJob.perform_now

      assert_empty @calls
    end
  end

  test "backfills yesterday while its window is still open" do
    travel_to AiQuestions.deadline_for(AiQuestions.today - 1) - 1.hour do
      Question.create!(title: "Есть", body: "Тело", answer_type: "text",
        deadline: 7.days.from_now, reference_answer: "Ответ",
        author: users(:one), ai_generated: true, ai_batch: AiQuestions.today)

      AiPackEnsureJob.perform_now

      assert_equal [ { batch: (AiQuestions.today - 1).to_s } ], @calls
    end
  end

  test "skips yesterday once its window closed" do
    travel_to AiQuestions.deadline_for(AiQuestions.today - 1) + 1.hour do
      Question.create!(title: "Есть", body: "Тело", answer_type: "text",
        deadline: 7.days.from_now, reference_answer: "Ответ",
        author: users(:one), ai_generated: true, ai_batch: AiQuestions.today)

      AiPackEnsureJob.perform_now

      assert_empty @calls
    end
  end
end
