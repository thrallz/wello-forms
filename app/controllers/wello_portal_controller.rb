# frozen_string_literal: true

# Wello Forms client portal: documents sent to the signed-in client's email address.
# Signing and downloading still happen on the standard public signing pages.
class WelloPortalController < ApplicationController
  skip_authorization_check

  def index
    return redirect_to root_path unless current_user.wello_client?

    submitters = Submitter.where(account_id: current_user.account_id)
                          .where('LOWER(submitters.email) = ?', current_user.email.to_s.downcase)
                          .joins(:submission)
                          .where(submissions: { archived_at: nil })
                          .preload(submission: :template)
                          .order(id: :desc)

    @pending = submitters.where(completed_at: nil, declined_at: nil).limit(100)
    @completed = submitters.where.not(completed_at: nil).limit(100)
  end
end
