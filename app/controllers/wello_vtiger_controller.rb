# frozen_string_literal: true

# Entry point for the "Wello Forms" button inside Vtiger:
#   /vtiger/open?module=Accounts&record=123
# Imports (or refreshes) the client from Vtiger and opens the send-form page.
class WelloVtigerController < ApplicationController
  def open
    authorize!(:create, WelloClient.new(account: current_account))
    authorize!(:create, Submission.new(account: current_account))

    unless Wello::Vtiger.configured?(current_account)
      return redirect_to wello_clients_path, alert: I18n.t('wello_vtiger_not_configured')
    end

    client = Wello::Vtiger.build_client(account: current_account, user: current_user,
                                        module_name: params[:module].to_s, record_id: params[:record].to_s,
                                        number: params[:number].presence)

    if client.persisted? && !can?(:read, client)
      return redirect_to wello_clients_path,
                         alert: I18n.t('wello_client_assigned_to_someone_else',
                                       name: client.assigned_user&.full_name.presence || client.assigned_user&.email)
    end

    client.save!

    redirect_to new_wello_client_send_form_path(client, template_id: params[:template_id].presence)
  rescue Wello::Vtiger::Error, ActiveRecord::RecordInvalid => e
    redirect_to wello_clients_path, alert: e.message
  end

  def search
    authorize!(:create, WelloClient.new(account: current_account))

    @configured = Wello::Vtiger.configured?(current_account)
    @results = @configured && params[:q].present? ? Wello::Vtiger.search(current_account, params[:q]) : []
  rescue Wello::Vtiger::Error => e
    @results = []
    flash.now[:alert] = e.message
  end

  def sync
    client = WelloClient.find(params[:wello_client_id])
    authorize!(:update, client)

    Wello::Vtiger.sync_client(client)

    redirect_to wello_client_path(client), notice: I18n.t('wello_client_synced')
  rescue Wello::Vtiger::Error, ActiveRecord::RecordInvalid => e
    redirect_to wello_client_path(client), alert: e.message
  end
end
