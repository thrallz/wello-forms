# frozen_string_literal: true

require 'net/http'

module Wello
  # Twilio SMS for signing links. Credentials live in the account's encrypted
  # "sms_configs" EncryptedConfig (Settings → SMS).
  module Sms
    CONFIG_KEY = 'sms_configs'
    TWILIO_API_URL = 'https://api.twilio.com/2010-04-01/Accounts/%<sid>s/Messages.json'

    Error = Class.new(StandardError)

    module_function

    def config(account)
      value = EncryptedConfig.find_by(account:, key: CONFIG_KEY)&.value

      value.is_a?(Hash) ? value : {}
    end

    def configured?(account)
      c = config(account)

      c['provider'] == 'twilio' && c['account_sid'].present? && c['auth_token'].present? &&
        (c['from_number'].present? || c['messaging_service_sid'].present?)
    end

    def normalize_phone(phone)
      digits = phone.to_s.gsub(/[^\d+]/, '')

      return if digits.delete('+').length < 10
      return digits if digits.start_with?('+')
      return "+1#{digits}" if digits.length == 10
      return "+#{digits}" if digits.length == 11 && digits.start_with?('1')

      "+#{digits}"
    end

    def send_message(account, to:, body:, sms_config: nil)
      c = sms_config || config(account)
      phone = normalize_phone(to)

      raise Error, 'SMS is not configured' unless c['account_sid'].present? && c['auth_token'].present?
      raise Error, "Invalid phone number: #{to}" if phone.blank?

      uri = URI(format(TWILIO_API_URL, sid: c['account_sid']))
      request = Net::HTTP::Post.new(uri)
      request.basic_auth(c['account_sid'], c['auth_token'])

      form = { 'To' => phone, 'Body' => body }
      if c['messaging_service_sid'].present?
        form['MessagingServiceSid'] = c['messaging_service_sid']
      else
        form['From'] = c['from_number']
      end
      request.set_form_data(form)

      response = Net::HTTP.start(uri.host, uri.port, use_ssl: true, open_timeout: 10, read_timeout: 15) do |http|
        http.request(request)
      end

      data = JSON.parse(response.body.presence || '{}')

      raise Error, data['message'].presence || "Twilio error #{response.code}" unless response.is_a?(Net::HTTPSuccess)

      data
    end

    def should_send_invitation?(submitter)
      submitter.preferences['send_sms'] == true &&
        submitter.phone.present? &&
        !submitter.declined_at? &&
        !submitter.completed_at? &&
        configured?(submitter.account)
    end

    def enqueue_invitation(submitter, delay_seconds: nil)
      return unless should_send_invitation?(submitter)

      if delay_seconds
        WelloSendSubmitterInvitationSmsJob.perform_in(delay_seconds, 'submitter_id' => submitter.id)
      else
        WelloSendSubmitterInvitationSmsJob.perform_async('submitter_id' => submitter.id)
      end
    end

    def invitation_body(submitter)
      name = submitter.submission.name.presence || submitter.submission.template&.name || 'a document'
      link = ReplaceEmailVariables.build_submitter_link(submitter, 'click_sms')

      I18n.t('wello_sms_invitation', account: submitter.account.name, document: name, link:)
    end
  end
end
