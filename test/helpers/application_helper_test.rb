require "test_helper"

class ApplicationHelperTest < ActionView::TestCase
  test "initials take first letters of first two words" do
    assert_equal "ИИ", initials("Иванов Иван Иванович")
    assert_equal "А", initials("Анна")
  end

  test "time_left pluralizes ru correctly" do
    assert_equal "3 дня", time_left(Time.current + 3.days + 5.minutes)
    assert_equal "1 час", time_left(Time.current + 1.hour + 1.minute)
    assert_equal "2 часа", time_left(Time.current + 2.hours + 1.minute)
    assert_equal "завершён", time_left(1.minute.ago)
  end

  test "ago_ru humanizes recent times" do
    assert_equal "только что", ago_ru(Time.current)
    assert_equal "5 минут назад", ago_ru(320.seconds.ago)
    assert_match(/\d{2}\.\d{2} \d{2}:\d{2}/, ago_ru(10.days.ago))
  end

  test "jury_summary falls back when check hasn't finished" do
    attempt = Attempt.new(jury_label: nil)

    assert_equal "проверка не завершена", jury_summary(attempt)
    attempt.jury_label = "partial"
    attempt.jury_score = 0.5

    assert_equal "частично · 0.5", jury_summary(attempt)
  end
end
