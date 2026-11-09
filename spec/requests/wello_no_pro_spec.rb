# frozen_string_literal: true

RSpec.describe 'Wello Forms without DocuSeal Pro' do
  let(:account) { create(:account) }
  let!(:admin) { create(:user, account:, role: User::ADMIN_ROLE) }

  it 'shows the sign-in form instead of the DocuSeal landing page' do
    get root_path

    expect(response).to redirect_to(new_user_session_path)
  end

  it 'sends a fresh install to setup first' do
    User.delete_all

    get root_path

    expect(response).to redirect_to(setup_index_path)
  end

  describe 'settings' do
    before { sign_in(admin) }

    it 'has no Plans, SSO or Pro upsell links, and Console opens the jobs dashboard' do
      get settings_profile_index_path

      expect(response.body).not_to include('Plans', '/settings/sso', 'Unlock with DocuSeal Pro', 'console.docuseal')
      expect(response.body).to include('href="/sidekiq"')
    end

    it 'has no SSO page' do
      expect { Rails.application.routes.recognize_path('/settings/sso') }
        .to raise_error(ActionController::RoutingError)
    end

    it 'shows no Pro upsells on settings pages' do
      [settings_personalization_path, settings_notifications_path, settings_esign_path].each do |path|
        get path

        expect(response.body).not_to include('Unlock with DocuSeal Pro'), "found Pro upsell on #{path}"
      end
    end
  end
end
