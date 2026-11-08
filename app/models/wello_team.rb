# frozen_string_literal: true

# == Schema Information
#
# Table name: wello_teams
#
#  id         :bigint           not null, primary key
#  name       :string           not null
#  created_at :datetime         not null
#  updated_at :datetime         not null
#  account_id :bigint           not null
#
class WelloTeam < ApplicationRecord
  belongs_to :account
  has_many :users, dependent: :nullify

  validates :name, presence: true, uniqueness: { scope: :account_id, case_sensitive: false }

  scope :ordered, -> { order(:name) }
end
