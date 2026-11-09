# frozen_string_literal: true

RSpec.describe Wello::VtigerSignatures do
  let(:account) { create(:account) }
  let(:user) { create(:user, account:) }
  let(:base) { 'https://acme.od2.vtiger.com/restapi/v1/vtiger/default' }
  let(:template) { create(:template, account:, author: user) }
  let(:client) do
    WelloClient.create!(account:, dba_name: 'Lux Nails', email: 'owner@lux.test', vtiger_id: '11x42',
                        vtiger_module: 'Accounts')
  end
  let(:submission) do
    create(:submission, :with_submitters, template:, created_by_user: user).tap do |s|
      s.update!(wello_client: client)
      s.submitters.first.update!(email: 'owner@lux.test', name: 'Linh Tran', sent_at: Time.zone.parse('2026-11-08'))
    end
  end

  let(:describe_result) do
    {
      labelFields: 'cf_title',
      fields: [
        { name: 'cf_title', label: 'Document Name', type: { name: 'string' } },
        { name: 'cf_status', label: 'Status', type: { name: 'picklist' } },
        { name: 'cf_signer', label: 'Signer Name', type: { name: 'string' } },
        { name: 'cf_signer_email', label: 'Signer Email', type: { name: 'email' } },
        { name: 'cf_sent', label: 'Sent On', type: { name: 'date' } },
        { name: 'cf_signed', label: 'Signed On', type: { name: 'date' } },
        { name: 'cf_link', label: 'Document Link', type: { name: 'url' } },
        { name: 'cf_org', label: 'Organization', type: { name: 'reference', refersTo: ['Accounts'] } },
        { name: 'assigned_user_id', label: 'Assigned To', type: { name: 'owner' } }
      ]
    }
  end

  def ok(result)
    { body: { success: true, result: }.to_json }
  end

  def posted_element(request)
    JSON.parse(CGI.parse(request.body)['element'].first)
  end

  before do
    EncryptedConfig.create!(account:, key: Wello::Vtiger::CONFIG_KEY,
                            value: { 'url' => 'https://acme.od2.vtiger.com', 'username' => 'u', 'access_key' => 'k' })
    stub_request(:get, "#{base}/me").to_return(ok(id: '19x1', user_name: 'api'))
  end

  it 'matches fields by label' do
    map = described_class.build_field_map(describe_result.deep_stringify_keys)

    expect(map).to include(name: 'cf_title', status: 'cf_status', signer_name: 'cf_signer', link: 'cf_link',
                           sent_on: 'cf_sent', signed_on: 'cf_signed', signer_email: 'cf_signer_email')
    expect(map[:references]).to eq('Accounts' => 'cf_org')
  end

  context 'with the Wello Signatures module in Vtiger' do
    before do
      stub_request(:get, "#{base}/listtypes?fieldTypeList=null")
        .to_return(ok(types: %w[Accounts WelloSignatures],
                      information: { Accounts: { label: 'Organizations' },
                                     WelloSignatures: { label: 'Wello Signatures' } }))
      stub_request(:get, "#{base}/describe?elementType=WelloSignatures").to_return(ok(describe_result))
    end

    it 'creates the sign request, then revises its status' do
      create_stub = stub_request(:post, "#{base}/create")
                    .with { |req| CGI.parse(req.body)['elementType'] == ['WelloSignatures'] }
                    .to_return(ok(id: '55x7'))
      revise_stub = stub_request(:post, "#{base}/revise").to_return(ok(id: '55x7'))

      expect(described_class.sync(submission)).to eq('sent')
      expect(submission.reload.wello_vtiger_signature_id).to eq('55x7')
      expected = { 'cf_title' => template.name, 'cf_status' => 'Sent', 'cf_signer' => 'Linh Tran',
                   'cf_signer_email' => 'owner@lux.test', 'cf_sent' => '2026-11-08', 'cf_org' => '11x42',
                   'assigned_user_id' => '19x1' }
      expect(create_stub.with { |req| posted_element(req).slice(*expected.keys) == expected }).to have_been_requested
      expect(create_stub.with { |req| posted_element(req)['cf_link'].include?("/submissions/#{submission.id}") })
        .to have_been_requested

      submission.submitters.first.update!(opened_at: Time.current)
      expect(described_class.sync(submission.reload)).to eq('viewed')
      expect(revise_stub.with { |req| posted_element(req).values_at('id', 'cf_status') == %w[55x7 Viewed] })
        .to have_been_requested

      described_class.sync(submission.reload)
      expect(revise_stub).to have_been_requested.once
    end

    it 'marks it signed and adds the signed copy to Documents' do
      submission.update!(wello_vtiger_signature_id: '55x7', wello_vtiger_status: 'viewed', completed_at: Time.current)
      revise_stub = stub_request(:post, "#{base}/revise").to_return(ok(id: '55x7'))
      document_stub = stub_request(:post, "#{base}/create")
                      .with { |req| CGI.parse(req.body)['elementType'] == ['Documents'] }
                      .to_return(ok(id: '15x9'))
      related_stub = stub_request(:post, "#{base}/add_related")
                     .with(body: { sourceRecordId: '11x42', relatedRecordId: '15x9', relationIdLabel: 'Documents' })
                     .to_return(ok(message: 'successful'))

      expect(described_class.sync(submission)).to eq('signed')

      expect(revise_stub.with { |req| posted_element(req)['cf_status'] == 'Signed' }).to have_been_requested
      expect(document_stub.with { |req| posted_element(req)['filelocationtype'] == 'E' }).to have_been_requested
      expect(related_stub).to have_been_requested
      expect(submission.reload.wello_vtiger_document_id).to eq('15x9')
    end
  end

  context 'without the module' do
    before do
      stub_request(:get, "#{base}/listtypes?fieldTypeList=null")
        .to_return(ok(types: %w[Accounts], information: { Accounts: { label: 'Organizations' } }))
    end

    it 'posts a comment once the document is signed' do
      comment_stub = stub_request(:post, "#{base}/create")
                     .with { |req| CGI.parse(req.body)['elementType'] == ['ModComments'] }
                     .to_return(ok(id: '30x1'))
      submission.update!(completed_at: Time.current)

      2.times { described_class.sync(submission.reload) }

      expect(comment_stub).to have_been_requested.once
    end
  end
end
