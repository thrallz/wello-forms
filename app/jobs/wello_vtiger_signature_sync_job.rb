# frozen_string_literal: true

# Pushes a document's signing status to the "Wello Signatures" record in Vtiger.
class WelloVtigerSignatureSyncJob
  include Sidekiq::Job

  sidekiq_options retry: 5

  def perform(params = {})
    submission = Submission.find_by(id: params['submission_id'])

    return if submission.nil? || submission.wello_client&.vtiger_id.blank?
    return unless Wello::Vtiger.configured?(submission.account)

    Wello::VtigerSignatures.sync(submission)
  end
end
