require "test_helper"

class LogScrubTest < ActiveSupport::TestCase
  test "moderation texts are filtered from logs" do
    filtered = ActiveSupport::ParameterFilter.new(Rails.application.config.filter_parameters).filter(
      "question" => { "title" => "t", "body" => "b", "reference_answer" => "r",
                      "explanation" => "e", "tags_string" => "x" },
      "comment" => { "body" => "c" },
      "user" => { "name" => "n" }
    )

    assert_equal "[FILTERED]", filtered["question"]["title"]
    assert_equal "[FILTERED]", filtered["question"]["body"]
    assert_equal "[FILTERED]", filtered["question"]["reference_answer"]
    assert_equal "[FILTERED]", filtered["question"]["explanation"]
    assert_equal "[FILTERED]", filtered["user"]["name"]
    assert_equal "[FILTERED]", filtered["comment"]["body"]
  end
end
