# Current user's profile page, stats, rank, and settings.
class ProfilesController < ApplicationController
  before_action :set_user, only: %i[show edit update]

  # Shows stats and leaderboard rank for the current user.
  def show
    @published = @user.authored_questions.count
    @answered = @user.attempts.count
    @score = @user.attempts.joins(:question)
      .where(verdict: "correct")
      .where("questions.deadline <= ?", Time.current).count
    # Same ordering as LeaderboardsController so ranks agree.
    counts = Attempt.joins(:question)
      .where(verdict: "correct")
      .where("questions.deadline <= ?", Time.current)
      .group("attempts.user_id").count
    users = User.where(id: counts.keys).index_by(&:id)
    ranking = counts.filter_map { |uid, n| users[uid] && [ users[uid], n ] }
      .sort_by { |u, n| [ -n, u.name ] }
    me = ranking.index { |u, _| u.id == @user.id }
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

    # OAuth users have no password, so the live session counts as proof.
    def reauthenticated?
      return true if @user.provider.present?
      @user.authenticate(params[:user][:current_password].to_s).present?
    end
end
