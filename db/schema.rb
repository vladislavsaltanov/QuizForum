# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.1].define(version: 2026_09_21_220000) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"

  create_table "attempts", force: :cascade do |t|
    t.text "body", default: "", null: false
    t.datetime "created_at", null: false
    t.string "language"
    t.bigint "question_id", null: false
    t.jsonb "selected", default: [], null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.string "verdict", default: "pending", null: false
    t.index ["question_id", "user_id"], name: "index_attempts_on_question_id_and_user_id", unique: true
    t.index ["question_id"], name: "index_attempts_on_question_id"
    t.index ["user_id"], name: "index_attempts_on_user_id"
  end

  create_table "comments", force: :cascade do |t|
    t.text "body", null: false
    t.datetime "created_at", null: false
    t.bigint "question_id", null: false
    t.string "status", default: "pending", null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["question_id"], name: "index_comments_on_question_id"
    t.index ["user_id"], name: "index_comments_on_user_id"
  end

  create_table "questions", force: :cascade do |t|
    t.string "answer_type", default: "text", null: false
    t.bigint "author_id", null: false
    t.text "body", default: "", null: false
    t.datetime "created_at", null: false
    t.datetime "deadline", null: false
    t.text "explanation"
    t.jsonb "options", default: [], null: false
    t.text "reference_answer", default: "", null: false
    t.string "tags", default: [], null: false, array: true
    t.string "title", null: false
    t.datetime "updated_at", null: false
    t.index ["author_id"], name: "index_questions_on_author_id"
  end

  create_table "reports", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "question_id", null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["question_id", "user_id"], name: "index_reports_on_question_id_and_user_id", unique: true
    t.index ["question_id"], name: "index_reports_on_question_id"
    t.index ["user_id"], name: "index_reports_on_user_id"
  end

  create_table "sessions", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "ip_address"
    t.datetime "updated_at", null: false
    t.string "user_agent"
    t.bigint "user_id", null: false
    t.index ["user_id"], name: "index_sessions_on_user_id"
  end

  create_table "users", force: :cascade do |t|
    t.boolean "admin", default: false, null: false
    t.datetime "created_at", null: false
    t.string "display_role"
    t.string "email", null: false
    t.datetime "email_confirmed_at"
    t.string "name", null: false
    t.string "password_digest", null: false
    t.string "provider"
    t.string "uid"
    t.datetime "updated_at", null: false
    t.index ["email"], name: "index_users_on_email", unique: true
    t.index ["provider", "uid"], name: "index_users_on_provider_and_uid", unique: true
  end

  add_foreign_key "attempts", "questions"
  add_foreign_key "attempts", "users"
  add_foreign_key "comments", "questions"
  add_foreign_key "comments", "users"
  add_foreign_key "questions", "users", column: "author_id"
  add_foreign_key "reports", "questions"
  add_foreign_key "reports", "users"
  add_foreign_key "sessions", "users"
end
