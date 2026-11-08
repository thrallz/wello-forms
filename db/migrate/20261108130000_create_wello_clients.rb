# frozen_string_literal: true

class CreateWelloClients < ActiveRecord::Migration[8.1]
  def change
    create_table :wello_clients do |t|
      t.references :account, null: false, foreign_key: true, index: true
      t.references :assigned_user, foreign_key: { to_table: :users }, index: true
      t.string :dba_name
      t.string :legal_name
      t.string :contact_first_name
      t.string :contact_last_name
      t.string :email
      t.string :phone
      t.string :merchant_id
      t.string :address_line1
      t.string :address_line2
      t.string :city
      t.string :state
      t.string :zip
      t.text :notes
      t.string :vtiger_id
      t.string :vtiger_module
      t.datetime :archived_at

      t.timestamps
    end

    add_index :wello_clients, %i[account_id vtiger_id], unique: true, where: 'vtiger_id IS NOT NULL'
    add_index :wello_clients, %i[account_id email]

    add_reference :submissions, :wello_client, foreign_key: true, index: true
  end
end
