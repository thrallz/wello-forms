# frozen_string_literal: true

# Send / re-send a signer's link by SMS from the submission page.
class WelloSubmitterSmsController < ApplicationController
  load_and_authorize_resource :submitter, id_param: :submitter_id

  def create
    authorize!(:update, @submitter.submission)

    if @submitter.phone.blank? || !Wello::Sms.configured?(current_account)
      return redirect_back fallback_location: submission_path(@submitter.submission),
                           alert: I18n.t('wello_sms_not_available')
    end

    WelloSendSubmitterInvitationSmsJob.new.perform('submitter_id' => @submitter.id)

    redirect_back fallback_location: submission_path(@submitter.submission), notice: I18n.t('wello_sms_sent')
  rescue Wello::Sms::Error => e
    redirect_back fallback_location: submission_path(@submitter.submission), alert: e.message
  end
end
