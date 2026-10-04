require "test_helper"

# Avatars are drawn client-side from data-blobatar; the server only guarantees
# the seed and the initials fallback, which is what these tests pin.
class BlobatarAvatarTest < ActionDispatch::IntegrationTest
  setup do
    @author = users(:one)
    sign_in_as(users(:two))
  end

  # A stale vendored file or a renamed import breaks module linking, which kills
  # this whole file — Turbo included — while the Rails suite stays green.
  test "vendored bundles export every name application.js imports" do
    imports = Rails.root.join("app/javascript/application.js").read
      .scan(/^import \{([^}]+)\} from "([^"]+)"/)
      .to_h { |names, specifier| [ specifier, names.split(",").map(&:strip) ] }

    assert_not_empty imports
    packages = Rails.application.importmap.packages

    imports.each do |specifier, names|
      file = Rails.root.join("vendor/javascript", packages.fetch(specifier).path)
      exported = file.read.scan(/export\s*\{([^}]*)\}/).flatten.join(",")
        .split(",").map { _1.split(" as ").last.strip }

      names.each do |name|
        assert_includes exported, name, "#{file.basename} must export #{name} for #{specifier}"
      end
    end
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
    assert_select ".qf-attempt-who [data-blobatar='One']", count: 1
  end

  test "each comment carries its author's avatar seed" do
    questions(:closed_single).comments.create!(user: @author, body: "спасибо", status: "approved")
    get question_path(questions(:closed_single)), params: { tab: "comments" }

    assert_response :success
    assert_select ".qf-msg [data-blobatar='One']", count: 1
  end

  test "question page seeds the author avatar" do
    get question_path(questions(:closed_single))

    assert_response :success
    assert_select ".qf-author-card [data-blobatar='One']", count: 1
  end

  test "leaderboard seeds an avatar per ranked user" do
    Attempt.create!(question: questions(:closed_single), user: users(:one), selected: [ "0" ])
    get leaderboard_path

    assert_response :success
    assert_select ".qf-board .qf-row [data-blobatar='One']", count: 1
  end
end
