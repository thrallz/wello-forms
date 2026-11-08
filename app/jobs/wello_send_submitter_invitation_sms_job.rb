# frozen_string_literal: true

class WelloSendSubmitterInvitationSmsJob
  include Sidekiq::Job

  sidekiq_options queue: :sms, retry: 3

  def perform(params = {})
    submitter = Submitter.find_by(id: params['submitter_id'])

    return unless submitter
    return if submitter.completed_at? || submitter.declined_at?
    return if submitter.submission.archived_at? || submitter.submission.expired?
    return if submitter.template&.archived_at?
    return unless Wello::Sms.configured?(submitter.account)

    response = Wello::Sms.send_message(submitter.account, to: submitter.phone,
                                                          body: Wello::Sms.invitation_body(submitter))

    SubmissionEvent.create!(submitter:, event_type: 'send_sms',
                            data: { segments: response['num_segments'].to_i.clamp(1, 10), sid: response['sid'] })

    submitter.sent_at ||= Time.current
    submitter.save!
  end
end
