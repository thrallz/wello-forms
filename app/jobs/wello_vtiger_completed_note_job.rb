# frozen_string_literal: true

# Posts a comment on the client's Vtiger record when a document is fully signed.
class WelloVtigerCompletedNoteJob
  include Sidekiq::Job

  sidekiq_options retry: 3

  def perform(params = {})
    submission = Submission.find_by(id: params['submission_id'])
    client = submission&.wello_client

    return if client.nil? || client.vtiger_id.blank? || submission.completed_at.nil?
    return unless Wello::Vtiger.configured?(submission.account)

    name = submission.name.presence || submission.template&.name
    link = Rails.application.routes.url_helpers.submission_url(submission, **Docuseal.default_url_options)

    Wello::Vtiger.add_comment(submission.account, related_to: client.vtiger_id,
                                                  text: I18n.t('wello_vtiger_completed_note', document: name, link:))
  end
end
