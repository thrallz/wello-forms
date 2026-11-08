# frozen_string_literal: true

# == Schema Information
#
# Table name: wello_clients
#
#  id                 :bigint           not null, primary key
#  address_line1      :string
#  address_line2      :string
#  archived_at        :datetime
#  city               :string
#  contact_first_name :string
#  contact_last_name  :string
#  dba_name           :string
#  email              :string
#  legal_name         :string
#  merchant_id        :string
#  notes              :text
#  phone              :string
#  state              :string
#  vtiger_id          :string
#  vtiger_module      :string
#  zip                :string
#  created_at         :datetime         not null
#  updated_at         :datetime         not null
#  account_id         :bigint           not null
#  assigned_user_id   :bigint
#
class WelloClient < ApplicationRecord
  SEARCH_COLUMNS = %w[dba_name legal_name contact_first_name contact_last_name email phone merchant_id].freeze

  belongs_to :account
  belongs_to :assigned_user, class_name: 'User', optional: true
  has_many :submissions, dependent: :nullify

  before_validation :normalize_attributes

  validates :email, format: { with: URI::MailTo::EMAIL_REGEXP }, allow_blank: true
  validate :business_name_present
  validate :assigned_user_in_account

  scope :active, -> { where(archived_at: nil) }
  scope :archived, -> { where.not(archived_at: nil) }

  def self.search(query)
    return all if query.blank?

    term = "%#{sanitize_sql_like(query.to_s.strip)}%"
    condition = SEARCH_COLUMNS.map { |column| arel_table[column].matches(term) }.reduce(:or)

    digits = query.to_s.gsub(/\D/, '')

    if digits.length >= 3
      phone_digits = Arel::Nodes::NamedFunction.new(
        'REGEXP_REPLACE', [arel_table[:phone], Arel::Nodes.build_quoted('[^0-9]'),
                           Arel::Nodes.build_quoted(''), Arel::Nodes.build_quoted('g')]
      )
      condition = condition.or(phone_digits.matches("%#{digits}%"))
    end

    where(condition)
  end

  def display_name
    dba_name.presence || legal_name.presence || email
  end

  def contact_name
    [contact_first_name, contact_last_name].compact_blank.join(' ')
  end

  def address_lines
    [address_line1, address_line2, [city, [state, zip].compact_blank.join(' ')].compact_blank.join(', ')].compact_blank
  end

  private

  def normalize_attributes
    self.email = email.to_s.strip.downcase.presence
    self.phone = phone.to_s.strip.presence
    self.merchant_id = merchant_id.to_s.strip.presence

    %i[dba_name legal_name contact_first_name contact_last_name city state zip].each do |attr|
      self[attr] = self[attr].to_s.squish.presence
    end
  end

  def business_name_present
    return if dba_name.present? || legal_name.present?

    errors.add(:dba_name, :blank)
  end

  def assigned_user_in_account
    return if assigned_user.nil? || assigned_user.account_id == account_id

    errors.add(:assigned_user, :invalid)
  end
end
