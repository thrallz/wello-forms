# frozen_string_literal: true

module Wello
  # Mirrors Wello Forms documents into a custom "Wello Signatures" module in Vtiger
  # (built with Vtiger Module Builder), similar to Vtiger's DocuSign / Zoho Sign integrations:
  # a sign-request record per document with live status, and the signed copy in Documents.
  #
  # Fields are matched by their labels, so the internal names Module Builder assigns don't matter.
  module VtigerSignatures
    MODULE_LABEL_REGEXP = /\Awello\s*signatures?\z/i

    FIELD_LABELS = {
      name: ['document name', 'document', 'name', 'subject'],
      status: ['status', 'signature status'],
      signer_name: ['signer name', 'signer'],
      signer_email: ['signer email', 'email'],
      sent_on: ['sent on', 'sent date', 'date sent'],
      signed_on: ['signed on', 'signed date', 'date signed', 'completed on'],
      link: ['document link', 'link', 'url', 'wello link']
    }.freeze

    STATUSES = { 'sent' => 'Sent', 'viewed' => 'Viewed', 'signed' => 'Signed', 'declined' => 'Declined' }.freeze

    SYNC_EVENT_TYPES = %w[view_form decline_form complete_form].freeze

    module_function

    def normalize(label)
      label.to_s.downcase.gsub(/[^a-z0-9]+/, ' ').squish
    end

    def module_name(account)
      configured = Wello::Vtiger.config(account)['signature_module'].presence

      return configured if configured

      Rails.cache.fetch("wello_vtiger_signature_module:#{account.id}", expires_in: 10.minutes) do
        info = Wello::Vtiger.request(account, 'listtypes', { fieldTypeList: 'null' })['information'] || {}

        info.find { |name, data| data['label'].to_s.match?(MODULE_LABEL_REGEXP) || name.match?(MODULE_LABEL_REGEXP) }
            &.first.to_s
      end.presence
    end

    def field_map(account, module_name = self.module_name(account))
      return {} if module_name.blank?

      describe = Rails.cache.fetch("wello_vtiger_describe:#{account.id}:#{module_name}", expires_in: 10.minutes) do
        Wello::Vtiger.request(account, 'describe', { elementType: module_name })
      end

      build_field_map(describe)
    end

    def build_field_map(describe)
      fields = describe['fields'] || []
      map = { references: {} }

      FIELD_LABELS.each do |key, labels|
        field = labels.lazy.map { |label| fields.find { |f| normalize(f['label']) == label } }.find(&:itself)
        map[key] = field['name'] if field && map.values.exclude?(field['name'])
      end

      map[:name] ||= describe['labelFields'].to_s.split(',').first.presence

      fields.each do |field|
        next unless field.dig('type', 'name') == 'reference'

        Array(field.dig('type', 'refersTo')).each { |target| map[:references][target] ||= field['name'] }
      end

      map
    end

    def enabled?(account)
      Wello::Vtiger.configured?(account) && module_name(account).present?
    rescue Wello::Vtiger::Error
      false
    end

    def enqueue_sync(submission)
      return if submission.wello_client_id.blank?

      client = submission.wello_client

      return if client&.vtiger_id.blank?
      return unless Wello::Vtiger.configured?(submission.account)

      WelloVtigerSignatureSyncJob.perform_async('submission_id' => submission.id)
    end

    def status_for(submission)
      submitters = submission.submitters.to_a

      return 'declined' if submitters.any?(&:declined_at?)
      return 'signed' if submission.completed_at?
      return 'viewed' if submitters.any?(&:opened_at?)

      'sent'
    end

    def client_submitter(submission)
      client = submission.wello_client
      submitters = submission.submitters.sort_by(&:id)

      submitters.find { |s| client&.email.present? && s.email == client.email } || submitters.first
    end

    def document_link(submission, status)
      helpers = Rails.application.routes.url_helpers

      if status == 'signed'
        helpers.submissions_preview_url(submission.slug, **Docuseal.default_url_options)
      else
        helpers.submission_url(submission, **Docuseal.default_url_options)
      end
    end

    def element_for(submission, map, status)
      submitter = client_submitter(submission)
      client = submission.wello_client
      first_sent = submission.submitters.filter_map(&:sent_at).min || submission.created_at

      values = {
        name: submission.name.presence || submission.template&.name || "Document ##{submission.id}",
        status: STATUSES[status],
        signer_name: submitter&.name,
        signer_email: submitter&.email,
        sent_on: first_sent.to_date.iso8601,
        signed_on: submission.completed_at&.to_date&.iso8601,
        link: document_link(submission, status)
      }

      element = values.each_with_object({}) do |(key, value), acc|
        acc[map[key]] = value if map[key].present? && !value.nil?
      end

      reference = map[:references][client.vtiger_module.presence || 'Accounts']
      element[reference] = client.vtiger_id if reference

      element
    end

    # Creates or updates the Wello Signature record in Vtiger. Returns the new status.
    def sync(submission)
      account = submission.account
      client = submission.wello_client
      status = status_for(submission)
      module_name = self.module_name(account)

      return post_completed_comment(submission, status) if module_name.blank?

      if status != submission.wello_vtiger_status || submission.wello_vtiger_signature_id.blank?
        upsert_signature(submission, module_name, field_map(account, module_name), status)
      end

      attach_signed_document(submission, client) if status == 'signed' && submission.wello_vtiger_document_id.blank?

      submission.update_columns(wello_vtiger_status: status)

      status
    end

    def upsert_signature(submission, module_name, map, status)
      account = submission.account
      element = element_for(submission, map, status)

      if submission.wello_vtiger_signature_id.present?
        Wello::Vtiger.request(account, 'revise',
                              { element: element.merge('id' => submission.wello_vtiger_signature_id).to_json },
                              method: :post)
      else
        element['assigned_user_id'] = Wello::Vtiger.me(account)['id']

        record = Wello::Vtiger.request(account, 'create',
                                       { elementType: module_name, element: element.to_json }, method: :post)

        submission.update_columns(wello_vtiger_signature_id: record['id'])
      end
    end

    # Adds the signed copy to the client's Documents tab in Vtiger (as a web link to the signed PDF).
    def attach_signed_document(submission, client)
      account = submission.account
      title = I18n.t('wello_vtiger_signed_document_title',
                     document: submission.name.presence || submission.template&.name || submission.id)

      document = Wello::Vtiger.request(account, 'create', {
                                         elementType: 'Documents',
                                         element: {
                                           notes_title: title,
                                           filelocationtype: 'E',
                                           filename: document_link(submission, 'signed'),
                                           filestatus: '1',
                                           assigned_user_id: Wello::Vtiger.me(account)['id']
                                         }.to_json
                                       }, method: :post)

      submission.update_columns(wello_vtiger_document_id: document['id'])

      Wello::Vtiger.request(account, 'add_related', {
                              sourceRecordId: client.vtiger_id,
                              relatedRecordId: document['id'],
                              relationIdLabel: 'Documents'
                            }, method: :post)
    rescue Wello::Vtiger::Error => e
      Rails.logger.warn("Wello Vtiger document attach failed for submission #{submission.id}: #{e.message}")
    end

    # Fallback when the Wello Signatures module doesn't exist: comment on the record once signed.
    def post_completed_comment(submission, status)
      return status unless status == 'signed' && submission.wello_vtiger_status != 'signed'

      Wello::Vtiger.add_comment(submission.account,
                                related_to: submission.wello_client.vtiger_id,
                                text: I18n.t('wello_vtiger_completed_note',
                                             document: submission.name.presence || submission.template&.name,
                                             link: document_link(submission, 'signed')))

      submission.update_columns(wello_vtiger_status: status)

      status
    end
  end
end
