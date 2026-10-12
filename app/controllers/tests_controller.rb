# Moodle-style tests: N inline tasks with tab navigation, optional password gate.
class TestsController < ApplicationController
  rate_limit to: 10, within: 3.minutes, only: %i[create authenticate attempt],
             with: -> { redirect_back fallback_location: root_path, alert: "Попробуйте позже." }

  # Feed of tests, newest first.
  def index
    @tests = Test.order(created_at: :desc).includes(:author, :test_tasks)
  end

  # Blank form with three empty task rows; blank rows are dropped on save.
  def new
    @test = Test.new(deadline: 7.days.from_now.change(sec: 0))
    @task_rows = 3.times.map { {} }
  end

  # Publishes a test with its tasks; blank password stays NULL (open test).
  def create
    @test = Current.user.authored_tests.build(test_params)
    @test.test_tasks = parse_tasks
    if @test.test_tasks.empty?
      @test.errors.add(:base, "Добавьте хотя бы одно задание.")
    end
    if @test.errors.empty? && @test.save
      redirect_to @test, notice: "Тест опубликован."
    else
      @task_rows = task_rows_from_params.presence || 3.times.map { {} }
      flash.now[:alert] = @test.errors.full_messages.to_sentence.presence || "Не удалось сохранить. Повторите."
      render :new, status: :unprocessable_entity
    end
  end

  # One task at a time via ?task=N inside a Turbo frame; scoreboard after deadline.
  def show
    @test = Test.includes(:author, test_tasks: :test_attempts).find(params[:id])
    @tasks = @test.test_tasks.to_a
    return render_gate unless @test.unlocked?(Current.user, session)
    @index = params[:task].to_i.clamp(0, [ @tasks.size - 1, 0 ].max)
    @task = @tasks[@index]
    @my_attempts = TestAttempt.where(test_task: @tasks, user: Current.user).index_by(&:test_task_id)
    @my_attempt = @my_attempts[@task&.id]
    @scoreboard = build_scoreboard if @test.closed?
  end

  # Checks the test password and remembers it in the session.
  def authenticate
    @test = Test.find(params[:id])
    if @test.authenticate(params[:password].to_s)
      session[@test.unlock_key] = true
      redirect_to @test, notice: "Доступ открыт."
    else
      redirect_to @test, alert: "Неверный пароль."
    end
  end

  # Saves the current user's attempt on the selected task. Rejects late posts;
  # the model + unique index reject second attempts on the same task.
  def attempt
    @test = Test.includes(:test_tasks).find(params[:id])
    return render_gate(status: :forbidden) unless @test.unlocked?(Current.user, session)
    return redirect_to @test, alert: "Дедлайн прошёл." if @test.closed?
    index = params[:task].to_i.clamp(0, [ @test.test_tasks.size - 1, 0 ].max)
    task = @test.test_tasks[index]
    record = task.test_attempts.build(attempt_params.merge(user: Current.user))
    if record.save
      redirect_to test_path(@test, task: index), notice: "Ответ записан."
    else
      redirect_to test_path(@test, task: index), alert: record.errors.full_messages.to_sentence
    end
  end

  private
    # Password form instead of the test body; strangers never see tasks.
    def render_gate(status: :ok)
      render :gate, status:
    end

    # Post-deadline totals per respondent from one preloaded relation.
    def build_scoreboard
      by_user = @tasks.flat_map(&:test_attempts).group_by(&:user_id)
      users = User.where(id: by_user.keys).index_by(&:id)
      by_user.filter_map do |uid, attempts|
        user = users[uid]
        next unless user
        verdicts = attempts.index_by(&:test_task_id)
        total = @tasks.sum { it.score_for(verdicts[it.id]&.verdict) }
        [ user, total ]
      end.sort_by { |u, total| [ -total, u.name ] }
    end

    # Whitelisted test form fields; tasks arrive as parallel arrays (see parse_tasks).
    def test_params
      params.expect(test: [ :title, :body, :deadline, :password, :max_points ])
    end

    # Zips parallel task form arrays into TestTask rows, skipping blank bodies.
    # Options come one per line; a leading "*" marks the correct ones.
    def parse_tasks
      bodies = Array(params[:tasks_body])
      types = Array(params[:tasks_answer_type])
      points = Array(params[:tasks_points])
      opts = Array(params[:tasks_options])
      bodies.each_with_index.filter_map do |body, i|
        body = body.to_s.strip
        next if body.empty?
        type = TestTask::ANSWER_TYPES.include?(types[i]) ? types[i] : "text"
        TestTask.new(body:, answer_type: type, position: i,
          points: points[i].to_i.clamp(0, 100),
          options: parse_task_options(opts[i]))
      end
    end

    # One option per line; "*" prefix means correct.
    def parse_task_options(raw)
      raw.to_s.lines.filter_map do |line|
        line = line.strip
        next if line.empty?
        correct = line.start_with?("*")
        { "text" => (correct ? line[1..].strip : line), "correct" => correct }
      end
    end

    # Echo the submitted rows back into the form after a failed save.
    def task_rows_from_params
      bodies = Array(params[:tasks_body])
      return [] if bodies.all?(&:blank?)
      bodies.each_with_index.map do |body, i|
        { "body" => body, "answer_type" => Array(params[:tasks_answer_type])[i],
          "points" => Array(params[:tasks_points])[i],
          "options" => Array(params[:tasks_options])[i] }
      end
    end

    # Whitelisted attempt form fields.
    def attempt_params
      params.expect(test_attempt: [ :body, { selected: [] } ])
    end
end
