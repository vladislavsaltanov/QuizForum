class ProfilesController < ApplicationController
  before_action :set_user, only: %i[show edit update]

  def show
    @published = @user.authored_questions.count
    @answered = @user.attempts.count
    @score = @user.attempts.joins(:question)
      .where(verdict: "correct")
      .where("questions.deadline <= ?", Time.current).count
    # ponytail: same ordering as LeaderboardsController so ranks match
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

  def edit
  end

  def update
    @user.assign_attributes(profile_params)
    if credentials_requested? && !reauthenticated?
      @user.errors.add(:current_password, :invalid)
      return render :edit, status: :unprocessable_entity
    end
    # ponytail: expect raises on empty filter — skip when nothing credential-like sent
    @user.assign_attributes(credential_params) if credentials_requested?
    if @user.save
      @user.sessions.where.not(id: Current.session.id).destroy_all if @user.saved_change_to_password_digest?
      redirect_to profile_path, notice: "Профиль обновлён."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  # ponytail: admin-only role grant — explicit attribute, never mass-assigned
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
    def set_user
      @user = Current.user
    end

    # ponytail: display_role is admin-set via grant_role panel — never user-editable via update
    def profile_params
      params.expect(user: [ :name ])
    end

    def credential_params
      params.expect(user: [ :email, :password, :password_confirmation ])
    end

    def credentials_requested?
      (params[:user].key?(:email) && params[:user][:email].to_s.strip.downcase != @user.email) ||
        params[:user][:password].to_s.present?
    end

    # OAuth users never set a password — their session is the proof
    def reauthenticated?
      return true if @user.provider.present?
      @user.authenticate(params[:user][:current_password].to_s).present?
    end
end
