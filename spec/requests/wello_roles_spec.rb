# frozen_string_literal: true

RSpec.describe 'Wello roles' do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account:, role: User::ADMIN_ROLE) }

  describe 'client' do
    let(:client) { create(:user, account:, role: User::CLIENT_ROLE, email: 'client@example.com') }
    let(:template) { create(:template, account:, author: admin) }

    before { sign_in(client) }

    it 'is sent from the dashboard to the portal' do
      get root_path

      expect(response).to redirect_to(wello_portal_path)
    end

    it 'is sent from back-office pages to the portal' do
      get settings_users_path

      expect(response).to redirect_to(wello_portal_path)
    end

    it 'sees documents sent to their email in the portal' do
      submission = create(:submission, :with_submitters, template:, created_by_user: admin)
      submission.submitters.first.update!(email: 'Client@Example.com')

      get wello_portal_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include(submission.submitters.first.slug)
    end

    it 'does not see documents sent to other people' do
      submission = create(:submission, :with_submitters, template:, created_by_user: admin)
      submission.submitters.first.update!(email: 'someone-else@example.com')

      get wello_portal_path

      expect(response.body).not_to include(submission.submitters.first.slug)
    end
  end

  describe 'teams settings' do
    it 'is available to admins' do
      sign_in(admin)

      post settings_wello_teams_path, params: { wello_team: { name: 'Sales' } }

      expect(WelloTeam.where(account:).pluck(:name)).to eq(['Sales'])
    end

    it 'is not available to employees' do
      sign_in(create(:user, account:, role: User::EMPLOYEE_ROLE))

      post settings_wello_teams_path, params: { wello_team: { name: 'Sales' } }

      expect(WelloTeam.count).to eq(0)
    end
  end

  describe 'admin assigning a team' do
    it 'sets and clears the team' do
      sign_in(admin)
      team = WelloTeam.create!(account:, name: 'Sales')
      employee = create(:user, account:, role: User::EMPLOYEE_ROLE)

      patch user_path(employee), params: { user: { wello_team_id: team.id, role: 'manager' } }
      expect(employee.reload).to have_attributes(wello_team_id: team.id, role: 'manager')

      patch user_path(employee), params: { user: { wello_team_id: '' } }
      expect(employee.reload.wello_team_id).to be_nil
    end
  end
end
