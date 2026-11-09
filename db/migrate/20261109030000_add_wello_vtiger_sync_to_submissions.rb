# frozen_string_literal: true

class AddWelloVtigerSyncToSubmissions < ActiveRecord::Migration[8.1]
  def change
    add_column :submissions, :wello_vtiger_signature_id, :string
    add_column :submissions, :wello_vtiger_document_id, :string
    add_column :submissions, :wello_vtiger_status, :string
  end
end
