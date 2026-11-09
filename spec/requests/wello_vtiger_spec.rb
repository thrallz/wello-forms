# frozen_string_literal: true

RSpec.describe 'Wello Vtiger button' do
  let(:account) { create(:account) }
  let(:user) { create(:user, account:, role: User::EMPLOYEE_ROLE) }
  let(:base) { 'https://acme.od2.vtiger.com/restapi/v1/vtiger/default' }

  before do
    EncryptedConfig.create!(account:, key: Wello::Vtiger::CONFIG_KEY,
                            value: { 'url' => 'https://acme.od2.vtiger.com', 'username' => 'u', 'access_key' => 'k' })
    stub_request(:get, "#{base}/describe?elementType=Accounts")
      .to_return(body: { success: true, result: { idPrefix: '11' } }.to_json)
    stub_request(:get, "#{base}/retrieve?id=11x42")
      .to_return(body: { success: true,
                         result: { id: '11x42', accountname: 'Lux Nails', email1: 'o@lux.test' } }.to_json)
    sign_in(user)
  end

  it 'imports the record and opens the send-form page' do
    get wello_vtiger_open_path(module: 'Accounts', record: '42')

    client = WelloClient.find_by(vtiger_id: '11x42')
    expect(client).to have_attributes(dba_name: 'Lux Nails', assigned_user: user)
    expect(response).to redirect_to(new_wello_client_send_form_path(client))
  end

  it 'does not open clients assigned to other reps' do
    other_rep = create(:user, account:, role: User::EMPLOYEE_ROLE)
    WelloClient.create!(account:, dba_name: 'Lux', vtiger_id: '11x42', assigned_user: other_rep)

    get wello_vtiger_open_path(module: 'Accounts', record: '42')

    expect(response).to redirect_to(wello_clients_path)
    expect(WelloClient.find_by(vtiger_id: '11x42').dba_name).to eq('Lux')
  end

  it 'opens from a Vtiger workflow link that uses the record number' do
    stub_request(:get, "#{base}/query")
      .with(query: { query: "SELECT id FROM Accounts WHERE account_no = 'ACC9' LIMIT 1;" })
      .to_return(body: { success: true, result: [{ id: '11x42' }] }.to_json)

    get wello_vtiger_open_path(module: 'Accounts', number: 'ACC9')

    expect(response).to redirect_to(new_wello_client_send_form_path(WelloClient.find_by(vtiger_id: '11x42')))
  end

  it 'shows Vtiger search results to import' do
    stub_request(:get, "#{base}/query")
      .with(query: hash_including({}))
      .to_return(body: { success: true, result: [{ id: '11x42', accountname: 'Lux Nails' }] }.to_json)

    get wello_vtiger_search_path(q: 'lux')

    expect(response.body).to include('Lux Nails', 'Import &amp; send')
  end
end

