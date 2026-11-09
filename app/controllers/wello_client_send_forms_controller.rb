# frozen_string_literal: true

# Employee workflow: pick a template for a client and send it for signing
# by email and/or SMS. The client's details pre-fill matching template fields.
class WelloClientSendFormsController < ApplicationController
  load_and_authorize_resource :wello_client, id_param: :wello_client_id

  before_action :authorize_send
  before_action :load_templates

  def new
    @template = @templates.find_by(id: params[:template_id]) if params[:template_id].present?
  end

  def create
    @template = @templates.find(params.require(:template_id))
    authorize!(:read, @template)

    submissions = Submissions.create_from_submitters(
      template: @template,
      user: current_user,
      source: :invite,
      submitters_order: params[:preserve_order] == '1' ? 'preserved' : 'random',
      submissions_attrs: [build_submission_attrs],
      params: { 'send_completed_email' => true }.with_indifferent_access
    )

    raise Submissions::CreateFromSubmitters::BaseError, I18n.t('wello_missing_recipient') if submissions.blank?

    Submission.where(id: submissions.map(&:id)).update_all(wello_client_id: @wello_client.id)
    submissions.each { |s| s.wello_client_id = @wello_client.id }

    WebhookUrls.enqueue_events(submissions, 'submission.created')
    Submissions.send_signature_requests(submissions)
    SearchEntries.enqueue_reindex(submissions)
    submissions.each { |submission| Wello::VtigerSignatures.enqueue_sync(submission) }

    redirect_to wello_client_path(@wello_client), notice: I18n.t('wello_form_sent')
  rescue Submissions::CreateFromSubmitters::BaseError, Wello::SendFormError => e
    flash.now[:alert] = e.message

    render :new, status: :unprocessable_content
  end

  private

  def authorize_send
    authorize!(:create, Submission.new(account: current_account))
  end

  def load_templates
    @templates = Template.accessible_by(current_ability).active.where(account_id: current_account.id)
                         .preload(:folder).order(:name)
  end

  def client_role_uuid
    uuid = params[:client_role_uuid].presence
    uuid = nil unless @template.submitters.any? { |s| s['uuid'] == uuid }

    uuid || @template.submitters.first&.dig('uuid')
  end

  def build_submission_attrs
    client_uuid = client_role_uuid
    send_email = params[:send_email] == '1'
    send_sms = params[:send_sms] == '1'

    validate_channels!(send_email:, send_sms:)

    submitters = @template.submitters.map do |template_submitter|
      if template_submitter['uuid'] == client_uuid
        client_submitter_attrs(template_submitter, send_email:, send_sms:)
      else
        other_submitter_attrs(template_submitter)
      end
    end

    attrs = { submitters: submitters.compact }.with_indifferent_access

    Submissions::NormalizeParamUtils.normalize_submissions_params!([attrs], @template)

    attrs
  end

  def client_submitter_attrs(template_submitter, send_email:, send_sms:)
    {
      uuid: template_submitter['uuid'],
      role: template_submitter['name'],
      name: @wello_client.contact_name.presence || @wello_client.display_name,
      email: @wello_client.email,
      phone: @wello_client.phone,
      send_email:,
      send_sms:,
      values: prefill_values(template_submitter['uuid'])
    }.compact_blank.merge(send_email:, send_sms:)
  end

  def prefill_values(submitter_uuid)
    return {} if params[:prefill] == '0'

    Wello::ClientPrefill.values(@wello_client, @template, submitter_uuid)
  end

  def other_submitter_attrs(template_submitter)
    other = params.dig(:other_submitters, template_submitter['uuid']) || {}
    email = other[:email].to_s.strip

    return if email.blank?

    { uuid: template_submitter['uuid'], role: template_submitter['name'],
      name: other[:name].to_s.strip.presence, email:, send_email: true }.compact
  end

  def validate_channels!(send_email:, send_sms:)
    raise Wello::SendFormError, I18n.t('wello_client_has_no_email') if send_email && @wello_client.email.blank?
    raise Wello::SendFormError, I18n.t('wello_client_has_no_phone') if send_sms && @wello_client.phone.blank?
    if send_sms && !Wello::Sms.configured?(current_account)
      raise Wello::SendFormError, I18n.t('wello_sms_not_available')
    end
    raise Wello::SendFormError, I18n.t('wello_choose_channel') unless send_email || send_sms
  end
end
