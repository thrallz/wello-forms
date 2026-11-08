# frozen_string_literal: true

# Settings → Teams. Admin-only (see Ability): create, rename and remove teams.
class WelloTeamsController < ApplicationController
  load_and_authorize_resource :wello_team, only: %i[update destroy]

  before_action only: %i[index create] do
    authorize!(:manage, WelloTeam.new(account: current_account))
  end

  def index
    @teams = WelloTeam.where(account: current_account).ordered.preload(:users)
    @team = WelloTeam.new
  end

  def create
    @team = WelloTeam.new(team_params.merge(account: current_account))

    if @team.save
      redirect_to settings_wello_teams_path, notice: I18n.t('wello_team_has_been_saved')
    else
      redirect_to settings_wello_teams_path, alert: @team.errors.full_messages.to_sentence
    end
  end

  def update
    if @wello_team.update(team_params)
      redirect_to settings_wello_teams_path, notice: I18n.t('wello_team_has_been_saved')
    else
      redirect_to settings_wello_teams_path, alert: @wello_team.errors.full_messages.to_sentence
    end
  end

  def destroy
    @wello_team.destroy!

    redirect_to settings_wello_teams_path, notice: I18n.t('wello_team_has_been_removed')
  end

  private

  def team_params
    params.require(:wello_team).permit(:name)
  end
end
