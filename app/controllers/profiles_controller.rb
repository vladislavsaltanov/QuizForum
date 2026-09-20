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
    @user.assign_attributes(credential_params)
    if @user.save
      @user.sessions.where.not(id: Current.session.id).destroy_all if @user.saved_change_to_password_digest?
      redirect_to profile_path, notice: "Профиль обновлён."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  private
    def set_user
      @user = Current.user
    end

    # ponytail: display_role is admin-set (seeds/console) — never user-editable
    def profile_params
      params.require(:user).permit(:name)
    end

    def credential_params
      params.require(:user).permit(:email, :password, :password_confirmation)
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
