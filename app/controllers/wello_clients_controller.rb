# frozen_string_literal: true

# Wello Forms client (merchant) directory: search, add, edit, archive,
# plus the client page with document history.
class WelloClientsController < ApplicationController
  load_and_authorize_resource :wello_client, parent: false, only: %i[index show edit update destroy]

  before_action :build_client, only: %i[new create]
  authorize_resource :wello_client, only: %i[new create]

  def index
    @wello_clients = params[:status] == 'archived' ? @wello_clients.archived : @wello_clients.active
    @wello_clients = @wello_clients.where(account_id: current_account.id)
                                   .search(params[:q])
                                   .preload(:assigned_user)
                                   .order(Arel.sql('LOWER(COALESCE(dba_name, legal_name)) ASC'))

    @pagy, @wello_clients = pagy(@wello_clients)

    @document_counts = Submission.accessible_by(current_ability)
                                 .where(wello_client_id: @wello_clients.map(&:id), archived_at: nil)
                                 .group(:wello_client_id).count
  end

  def show
    submissions = Submission.accessible_by(current_ability)
                            .where(wello_client_id: @wello_client.id, archived_at: nil)
                            .preload(:template, :created_by_user, :submitters)
                            .order(id: :desc)

    @pending_submissions = submissions.where(completed_at: nil).to_a
    @completed_submissions = submissions.where.not(completed_at: nil).to_a
  end

  def new
    render layout: turbo_native_android? ? 'plain' : true
  end

  def edit
    render layout: turbo_native_android? ? 'plain' : true
  end

  def create
    if @wello_client.save
      redirect_to wello_client_path(@wello_client), notice: I18n.t('wello_client_has_been_saved')
    else
      render turbo_stream: turbo_stream.replace(:modal, template: 'wello_clients/new'), status: :unprocessable_content
    end
  end

  def update
    if @wello_client.update(client_params)
      redirect_back fallback_location: wello_client_path(@wello_client), notice: I18n.t('wello_client_has_been_saved')
    else
      render turbo_stream: turbo_stream.replace(:modal, template: 'wello_clients/edit'), status: :unprocessable_content
    end
  end

  def destroy
    @wello_client.update!(archived_at: @wello_client.archived_at? ? nil : Time.current)

    redirect_to wello_clients_path, notice: I18n.t('wello_client_has_been_saved')
  end

  private

  def build_client
    @wello_client = WelloClient.new(account: current_account, assigned_user: current_user)
    @wello_client.assign_attributes(client_params)
  end

  def client_params
    return {} unless params.key?(:wello_client)

    permitted = params.require(:wello_client).permit(
      :dba_name, :legal_name, :contact_first_name, :contact_last_name, :email, :phone, :merchant_id,
      :address_line1, :address_line2, :city, :state, :zip, :notes, :assigned_user_id
    )

    if permitted.key?(:assigned_user_id) && assignable_user_ids.exclude?(permitted[:assigned_user_id].to_i)
      permitted.delete(:assigned_user_id)
    end

    permitted
  end

  def assignable_user_ids
    @assignable_user_ids ||= assignable_users.pluck(:id)
  end

  def assignable_users
    User.accessible_by(current_ability).where(account_id: current_account.id, archived_at: nil)
        .where.not(role: [User::CLIENT_ROLE, 'integration'])
  end
  helper_method :assignable_users
end
