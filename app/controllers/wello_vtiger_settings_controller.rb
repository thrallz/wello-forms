# frozen_string_literal: true

# Settings → Vtiger: instance URL, API user and access key, optional MID custom field.
class WelloVtigerSettingsController < ApplicationController
  before_action :load_encrypted_config
  authorize_resource :encrypted_config, parent: false

  def show
    load_signatures_check
  end

  def create
    value = vtiger_params
    previous = @encrypted_config.value.is_a?(Hash) ? @encrypted_config.value : {}
    value['access_key'] = previous['access_key'] if value['access_key'].blank?

    user = Wello::Vtiger.me(current_account, vtiger_config: value)

    @encrypted_config.update!(value:)
    clear_vtiger_cache

    name = user.is_a?(Hash) ? user['user_name'] || user['email1'] : value['username']

    redirect_to settings_wello_vtiger_path, notice: I18n.t('wello_vtiger_connected_as', name:)
  rescue Wello::Vtiger::Error => e
    flash.now[:alert] = e.message
    load_signatures_check

    render :show, status: :unprocessable_content
  end

  def destroy
    @encrypted_config.destroy! if @encrypted_config.persisted?

    redirect_to settings_wello_vtiger_path, notice: I18n.t('changes_have_been_saved')
  end

  private

  def load_signatures_check
    return unless Wello::Vtiger.configured?(current_account)

    module_name = Wello::VtigerSignatures.module_name(current_account)
    @signatures_check = { module_name:, map: Wello::VtigerSignatures.field_map(current_account, module_name) }
  rescue Wello::Vtiger::Error => e
    @signatures_check = { error: e.message }
  end

  def clear_vtiger_cache
    module_name = @encrypted_config.value['signature_module']

    Rails.cache.delete("wello_vtiger_signature_module:#{current_account.id}")
    Rails.cache.delete("wello_vtiger_describe:#{current_account.id}:#{module_name}") if module_name.present?
  end

  def load_encrypted_config
    @encrypted_config = EncryptedConfig.find_or_initialize_by(account: current_account, key: Wello::Vtiger::CONFIG_KEY)
  end

  def vtiger_params
    params.require(:encrypted_config).permit(value: %i[url username access_key mid_field signature_module])
          .fetch(:value, {}).to_h.transform_values { |v| v.to_s.strip }.compact_blank
  end
end
