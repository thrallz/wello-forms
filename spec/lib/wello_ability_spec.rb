# frozen_string_literal: true

RSpec.describe Ability do
  let(:account) { create(:account) }
  let(:team) { WelloTeam.create!(account:, name: 'Sales') }
  let(:other_team) { WelloTeam.create!(account:, name: 'Support') }

  let(:admin) { create(:user, account:, role: User::ADMIN_ROLE) }
  let(:manager) { create(:user, account:, role: User::MANAGER_ROLE, wello_team: team) }
  let(:employee) { create(:user, account:, role: User::EMPLOYEE_ROLE, wello_team: team) }
  let(:teammate) { create(:user, account:, role: User::EMPLOYEE_ROLE, wello_team: team) }
  let(:outsider) { create(:user, account:, role: User::EMPLOYEE_ROLE, wello_team: other_team) }
  let(:client) { create(:user, account:, role: User::CLIENT_ROLE) }

  let(:admin_template) { create(:template, account:, author: admin) }
  let(:employee_template) { create(:template, account:, author: employee) }

  def submission_by(user)
    create(:submission, template: admin_template, created_by_user: user)
  end

  describe 'admin' do
    subject(:ability) { described_class.new(admin) }

    it 'keeps full access' do
      expect(ability.can?(:manage, submission_by(outsider))).to be(true)
      expect(ability.can?(:update, employee_template)).to be(true)
      expect(ability.can?(:manage, EncryptedConfig.new(account:))).to be(true)
      expect(ability.can?(:manage, WelloTeam.new(account:))).to be(true)
    end
  end

  describe 'employee' do
    subject(:ability) { described_class.new(employee) }

    it 'can use any template but only edit their own' do
      expect(ability.can?(:read, admin_template)).to be(true)
      expect(ability.can?(:update, admin_template)).to be(false)
      expect(ability.can?(:update, employee_template)).to be(true)
      expect(ability.can?(:create, Template.new(account:, author: employee))).to be(true)
    end

    it 'sees only their own submissions' do
      own = submission_by(employee)
      teammates = submission_by(teammate)

      expect(ability.can?(:read, own)).to be(true)
      expect(ability.can?(:read, teammates)).to be(false)
      expect(Submission.accessible_by(ability)).to contain_exactly(own)
    end

    it 'can create submissions' do
      expect(ability.can?(:create, Submission.new(account:))).to be(true)
    end

    it 'has no access to account settings or teams' do
      expect(ability.can?(:read, EncryptedConfig.new(account:))).to be(false)
      expect(ability.can?(:read, AccountConfig.new(account:))).to be(false)
      expect(ability.can?(:read, WebhookUrl.new(account:))).to be(false)
      expect(ability.can?(:manage, WelloTeam.new(account:))).to be(false)
      expect(ability.can?(:create, User.new(account:))).to be(false)
    end

    it 'can manage their own profile only' do
      expect(ability.can?(:manage, employee)).to be(true)
      expect(ability.can?(:update, teammate)).to be(false)
    end
  end

  describe 'manager' do
    subject(:ability) { described_class.new(manager) }

    it "sees the whole team's submissions but not other teams'" do
      team_submission = submission_by(teammate)
      own_submission = submission_by(manager)
      other_submission = submission_by(outsider)

      expect(Submission.accessible_by(ability)).to contain_exactly(team_submission, own_submission)
      expect(ability.can?(:read, other_submission)).to be(false)
    end

    it "can edit team members' templates" do
      employee_template
      admin_template

      expect(ability.can?(:update, employee_template)).to be(true)
      expect(ability.can?(:update, admin_template)).to be(false)
    end

    it 'can see team members in the users list' do
      teammate
      outsider

      expect(User.accessible_by(ability)).to include(teammate)
      expect(User.accessible_by(ability)).not_to include(outsider)
    end
  end

  describe 'manager without a team' do
    let(:lone_manager) { create(:user, account:, role: User::MANAGER_ROLE) }

    it 'only sees their own submissions' do
      own = submission_by(lone_manager)
      submission_by(employee)

      expect(Submission.accessible_by(described_class.new(lone_manager))).to contain_exactly(own)
    end
  end

  describe 'client' do
    subject(:ability) { described_class.new(client) }

    it 'has no back-office access' do
      expect(ability.can?(:read, admin_template)).to be(false)
      expect(ability.can?(:read, submission_by(admin))).to be(false)
      expect(ability.can?(:create, Submission.new(account:))).to be(false)
      expect(ability.can?(:read, User)).to be(true) # own record only
      expect(User.accessible_by(ability)).to contain_exactly(client)
    end
  end
end
