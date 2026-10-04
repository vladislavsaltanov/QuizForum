require "test_helper"

# Avatars are drawn client-side from data-blobatar; the server only guarantees
# the seed and the initials fallback, which is what these tests pin.
class BlobatarAvatarTest < ActionDispatch::IntegrationTest
  setup do
    @author = users(:one)
    sign_in_as(users(:two))
  end

  test "profile seeds the avatar from the profile owner" do
    get profile_path

    assert_response :success
    assert_select ".qf-id-card [data-blobatar='Two']", count: 1
  end

  test "each answer carries its own avatar seed" do
    Attempt.create!(question: questions(:closed_single), user: @author, selected: [ "1" ])
    get question_path(questions(:closed_single))

    assert_response :success
    assert_select ".qf-attempt-head [data-blobatar='One']", count: 1
  end

  test "each comment carries its author's avatar seed" do
    questions(:closed_single).comments.create!(user: @author, body: "спасибо")
    get question_path(questions(:closed_single))

    assert_response :success
    assert_select ".qf-msg [data-blobatar='One']", count: 1
  end

  test "question page seeds the author avatar" do
    get question_path(questions(:closed_single))

    assert_response :success
    assert_select ".qf-author-card [data-blobatar='One']", count: 1
  end

  test "leaderboard seeds an avatar per ranked user" do
    Attempt.create!(question: questions(:closed_single), user: users(:one), selected: [ "1" ])
    get leaderboard_path

    assert_response :success
    assert_select ".qf-board .qf-row [data-blobatar='One']", count: 1
  end
end