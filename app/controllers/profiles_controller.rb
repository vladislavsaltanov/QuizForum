# Current user's profile page, stats, rank, and settings.
class ProfilesController < ApplicationController
  before_action :set_user, only: %i[show edit update]

  # Shows stats and leaderboard rank for the current user.
  def show
    @published = @user.authored_questions.count
    @answered = @user.attempts.count
    # Same ranking as LeaderboardsController so ranks agree.
    ranking = Attempt.revealed_points
    me = ranking.index { |u, _| u.id == @user.id }
    @score = me ? ranking[me][1] : 0
    @rank = me && me + 1
  end

  # Renders the profile edit form.
  def edit
  end

  # Updates the name and, after reauthentication, email or password.
  def update
    @user.assign_attributes(profile_params)
    if credentials_requested? && !reauthenticated?
      @user.errors.add(:current_password, :invalid)
      return render :edit, status: :unprocessable_entity
    end
    # expect raises on an empty filter, so only call it when credentials were sent.
    @user.assign_attributes(credential_params) if credentials_requested?
    if @user.save
      @user.sessions.where.not(id: Current.session.id).destroy_all if @user.saved_change_to_password_digest?
      redirect_to profile_path, notice: "Профиль обновлён."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  # Все тумблеры настроек одним запросом; cookie per-browser, все отмеченные
  # чекбоксы применяются атомично.
  def update_settings
    %i[hide_ai_banner old_cards old_test_wizard].each do |key|
      if params[key] == "1"
        cookies[key] = { value: "1", expires: 1.year }
      else
        cookies.delete(key)
      end
    end
    redirect_to profile_path, notice: "Настройки сохранены."
  end

  # Admin-only cosmetic role grant; never part of mass-assigned params.
  def grant_role
    return head(:forbidden) unless Current.user&.admin?
    target = User.find_by(id: params[:user_id].to_s.to_i)
    return redirect_to profile_path, alert: "Пользователь не найден." unless target
    role = params[:display_role].to_s.strip
    if role.length > 50
      return redirect_to profile_path, alert: "Роль слишком длинная (максимум 50 символов)."
    end
    target.update!(display_role: role.presence)
    redirect_to profile_path, notice: "Роль пользователя ##{target.id} обновлена."
  end

  # Admin-only forced regen of today's pack, UI twin of rake ai:regenerate.
  # Enqueues and redirects; the slow Gemini call never blocks the request.
  def regenerate_ai_pack
    return head(:forbidden) unless Current.user&.admin?
    AiDailyGenerateJob.perform_later(batch: AiQuestions.today.to_s, force: true)
    redirect_to profile_path, notice: "Генерация ИИ-рубрики на сегодня запущена."
  end

  private
    # Scopes every action to the signed-in user.
    def set_user
      @user = Current.user
    end

    # Only name is user-editable; display_role stays admin-set via grant_role.
    def profile_params
      params.expect(user: [ :name ])
    end

    # Email/password changes, applied only after reauthentication.
    def credential_params
      params.expect(user: [ :email, :password, :password_confirmation ])
    end

    # True when the form touched email or password.
    def credentials_requested?
      (params[:user].key?(:email) && params[:user][:email].to_s.strip.downcase != @user.email) ||
        params[:user][:password].to_s.present?
    end

    # Every credential change needs the current password, including OAuth
    # accounts (they set one via password reset first). No session-only bypass:
    # a hijacked session must not be enough to swap email+password.
    def reauthenticated?
      @user.authenticate(params[:user][:current_password].to_s).present?
    end
end
