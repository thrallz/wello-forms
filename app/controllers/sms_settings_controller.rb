# frozen_string_literal: true

# Settings → SMS. Wello Forms: Twilio credentials for sending signing links by SMS.
class SmsSettingsController < ApplicationController
  before_action :load_encrypted_config
  authorize_resource :encrypted_config, only: :index
  authorize_resource :encrypted_config, parent: false, except: :index

  def index; end

  def create
    value = sms_config_params
    value['auth_token'] = @encrypted_config.value['auth_token'] if value['auth_token'].blank? && @encrypted_config.value.is_a?(Hash)

    if value['account_sid'].blank? || value['auth_token'].blank? ||
       (value['from_number'].blank? && value['messaging_service_sid'].blank?)
      flash.now[:alert] = I18n.t('wello_sms_fields_required')

      return render :index, status: :unprocessable_content
    end

    if params[:test_phone].present?
      Wello::Sms.send_message(current_account, to: params[:test_phone],
                                               body: I18n.t('wello_sms_test_message', account: current_account.name),
                                               sms_config: value)
    end

    @encrypted_config.update!(value: value.merge('provider' => 'twilio'))

    redirect_to settings_sms_path, notice: params[:test_phone].present? ? I18n.t('wello_sms_test_sent') : I18n.t('changes_have_been_saved')
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
    params.require(:encrypted_config).permit(value: %i[account_sid auth_token from_number messaging_service_sid])
          .fetch(:value, {}).to_h.transform_values { |v| v.to_s.strip }.compact_blank
  end
end
