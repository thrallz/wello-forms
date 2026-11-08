# frozen_string_literal: true

class Ability
  include CanCan::Ability

  def initialize(user)
    return wello_client_abilities(user) if user.wello_client?
    return wello_staff_abilities(user) if user.wello_manager? || user.wello_employee?

    can %i[read create update], Template, Abilities::TemplateConditions.collection(user) do |template|
      Abilities::TemplateConditions.entity(template, user:, ability: 'manage')
    end

    can :destroy, Template, account_id: user.account_id
    can :manage, TemplateFolder, account_id: user.account_id
    can :manage, TemplateSharing, template: { account_id: user.account_id }
    can :manage, Submission, account_id: user.account_id
    can :manage, Submitter, account_id: user.account_id
    can :manage, User, account_id: user.account_id
    can :manage, EncryptedConfig, account_id: user.account_id
    can :manage, EncryptedUserConfig, user_id: user.id
    can :manage, AccountConfig, account_id: user.account_id
    can :manage, UserConfig, user_id: user.id
    can :manage, Account, id: user.account_id
    can :manage, AccessToken, user_id: user.id
    can :manage, McpToken, user_id: user.id
    can :manage, WebhookUrl, account_id: user.account_id
    can :manage, WelloTeam, account_id: user.account_id

    can :manage, :mcp
  end

  private

  # Wello Forms: managers and employees.
  # - Can use (read/send) every template in the account and create their own.
  # - Can edit/delete templates and see submissions created by themselves (employee)
  #   or anyone on their team (manager).
  # - No access to account settings, users admin, webhooks or API/MCP settings.
  def wello_staff_abilities(user)
    user_ids = user.wello_visible_user_ids

    can %i[read create], Template, Abilities::TemplateConditions.collection(user) do |template|
      Abilities::TemplateConditions.entity(template, user:, ability: 'read')
    end
    can %i[update destroy], Template, account_id: user.account_id, author_id: user_ids

    can %i[read create], TemplateFolder, account_id: user.account_id
    can %i[update destroy], TemplateFolder, account_id: user.account_id, author_id: user_ids

    can :create, Submission, account_id: user.account_id
    can :manage, Submission, account_id: user.account_id, created_by_user_id: user_ids

    can :create, Submitter, account_id: user.account_id
    can :manage, Submitter, account_id: user.account_id, submission: { created_by_user_id: user_ids }

    can :read, User, account_id: user.account_id, id: user_ids
    can :manage, User, id: user.id

    can :read, Account, id: user.account_id

    can :manage, EncryptedUserConfig, user_id: user.id
    can :manage, UserConfig, user_id: user.id
  end

  # Wello Forms: clients only use the /portal page (documents sent to their email).
  def wello_client_abilities(user)
    can :manage, User, id: user.id
    can :manage, EncryptedUserConfig, user_id: user.id
    can :manage, UserConfig, user_id: user.id
  end
end
