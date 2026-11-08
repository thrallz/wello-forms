# frozen_string_literal: true

class CreateWelloTeams < ActiveRecord::Migration[8.1]
  def change
    create_table :wello_teams do |t|
      t.references :account, null: false, foreign_key: true, index: true
      t.string :name, null: false

      t.timestamps
    end

    add_index :wello_teams, %i[account_id name], unique: true

    add_reference :users, :wello_team, foreign_key: true, index: true
  end
end
