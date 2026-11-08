# frozen_string_literal: true

RSpec.describe Wello::Vtiger do
  let(:account) { create(:account) }
  let(:user) { create(:user, account:) }
  let(:base) { 'https://acme.od2.vtiger.com/restapi/v1/vtiger/default' }

  before do
    EncryptedConfig.create!(account:, key: described_class::CONFIG_KEY,
                            value: { 'url' => 'acme.od2.vtiger.com/index.php', 'username' => 'api@acme.test',
                                     'access_key' => 'KEY', 'mid_field' => 'cf_mid' })

    stub_request(:get, "#{base}/describe?elementType=Accounts")
      .to_return(body: { success: true, result: { idPrefix: '11' } }.to_json)
    stub_request(:get, "#{base}/retrieve?id=11x42")
      .with(basic_auth: %w[api@acme.test KEY])
      .to_return(body: { success: true, result: {
        id: '11x42', accountname: 'Lux Nails', email1: 'owner@lux.test', phone: '555-1234',
        bill_street: '1 Main St', bill_city: 'Houston', bill_state: 'TX', bill_code: '77001', cf_mid: 'M-1'
      } }.to_json)
  end

  it 'builds a client from an organization record id' do
    client = described_class.build_client(account:, user:, module_name: 'Accounts', record_id: '42')

    expect(client).to have_attributes(
      dba_name: 'Lux Nails', email: 'owner@lux.test', vtiger_id: '11x42', vtiger_module: 'Accounts',
      city: 'Houston', merchant_id: 'M-1', assigned_user: user
    )
    expect(client).to be_new_record
  end

  it 'reuses the client already linked to the record' do
    existing = WelloClient.create!(account:, dba_name: 'Old', vtiger_id: '11x42', vtiger_module: 'Accounts')

    client = described_class.build_client(account:, user:, module_name: 'Accounts', record_id: '11x42')

    expect(client.id).to eq(existing.id)
    expect(client.dba_name).to eq('Lux Nails')
  end

  it 'reports Vtiger errors' do
    stub_request(:get, "#{base}/retrieve?id=11x7")
      .to_return(status: 403, body: { success: false, error: { message: 'Permission denied' } }.to_json)

    expect { described_class.build_client(account:, user:, module_name: 'Accounts', record_id: '11x7') }
      .to raise_error(described_class::Error, 'Permission denied')
  end
end
