# frozen_string_literal: true

# Settings → SMS. Wello Forms: Twilio credentials for sending signing links by SMS.
class SmsSettingsController < ApplicationController
  before_action :load_encrypted_config
  authorize_resource :encrypted_config, only: :index
  authorize_resource :encrypted_config, parent: false, except: :index

  def index; end

  def create
    value = sms_config_params

    unless valid_config?(value)
      flash.now[:alert] = I18n.t('wello_sms_fields_required')

      return render :index, status: :unprocessable_content
    end

    send_test_message(value) if params[:test_phone].present?

    @encrypted_config.update!(value: value.merge('provider' => 'twilio'))

    notice_key = params[:test_phone].present? ? 'wello_sms_test_sent' : 'changes_have_been_saved'

    redirect_to settings_sms_path, notice: I18n.t(notice_key)
  rescue Wello::Sms::Error, SocketError, Net::OpenTimeout, Net::ReadTimeout => e
    flash.now[:alert] = e.message

    render :index, status: :unprocessable_content
  end

  def destroy
    @encrypted_config.destroy! if @encrypted_config.persisted?

    redirect_to settings_sms_path, notice: I18n.t('changes_have_been_saved')
  end

  private

  def load_encrypted_config
    @encrypted_config =
      EncryptedConfig.find_or_initialize_by(account: current_account, key: Wello::Sms::CONFIG_KEY)
  end

  def sms_config_params
    permitted = params.require(:encrypted_config)
                      .permit(value: %i[account_sid auth_token from_number messaging_service_sid])
    value = permitted.fetch(:value, {}).to_h.transform_values { |v| v.to_s.strip }.compact_blank

    previous = @encrypted_config.value.is_a?(Hash) ? @encrypted_config.value : {}
    value['auth_token'] ||= previous['auth_token']

    value.compact_blank
  end

  def valid_config?(value)
    value['account_sid'].present? && value['auth_token'].present? &&
      (value['from_number'].present? || value['messaging_service_sid'].present?)
  end

  def send_test_message(value)
    Wello::Sms.send_message(current_account, to: params[:test_phone],
                                             body: I18n.t('wello_sms_test_message', account: current_account.name),
                                             sms_config: value)
  end
end
