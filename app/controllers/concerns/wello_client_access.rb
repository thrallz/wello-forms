# frozen_string_literal: true

# Wello Forms: users with the "client" role only get the client portal.
# Any page that requires sign-in (other than the portal, profile and MFA setup)
# sends them back to /portal. Public signing pages are unaffected.
module WelloClientAccess
  extend ActiveSupport::Concern

  CLIENT_ALLOWED_CONTROLLERS = %w[wello_portal profile mfa_setup settings].freeze

  included do
    before_action :wello_redirect_client_from_dashboard, if: -> { controller_path == 'dashboard' }
  end

  def authenticate_user!(*args, **kwargs)
    super

    wello_restrict_client_access
  end

  private

  def wello_redirect_client_from_dashboard
    redirect_to wello_portal_path if signed_in? && current_user.wello_client?
  end

  def wello_restrict_client_access
    return unless current_user&.wello_client?
    return if CLIENT_ALLOWED_CONTROLLERS.include?(controller_path)

    if request.format.html?
      redirect_to wello_portal_path
    else
      head :forbidden
    end
  end
end
