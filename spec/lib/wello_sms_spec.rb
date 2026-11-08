# frozen_string_literal: true

RSpec.describe Wello::Sms do
  let(:account) { create(:account, name: 'Wello Payment') }

  before do
    EncryptedConfig.create!(account:, key: described_class::CONFIG_KEY,
                            value: { 'provider' => 'twilio', 'account_sid' => 'AC123', 'auth_token' => 'secret',
                                     'from_number' => '+15550001111' })
  end

  it 'normalizes US phone numbers' do
    expect(described_class.normalize_phone('(555) 123-4567')).to eq('+15551234567')
    expect(described_class.normalize_phone('1 555 123 4567')).to eq('+15551234567')
    expect(described_class.normalize_phone('+44 20 7946 0958')).to eq('+442079460958')
    expect(described_class.normalize_phone('123')).to be_nil
  end

  it 'sends through the Twilio API' do
    stub = stub_request(:post, 'https://api.twilio.com/2010-04-01/Accounts/AC123/Messages.json')
           .with(basic_auth: %w[AC123 secret], body: { 'To' => '+15551234567', 'From' => '+15550001111', 'Body' => 'Hi' })
           .to_return(status: 201, body: { sid: 'SM1', num_segments: '1' }.to_json)

    described_class.send_message(account, to: '555-123-4567', body: 'Hi')

    expect(stub).to have_been_requested
  end

  it 'raises Twilio errors' do
    stub_request(:post, %r{api.twilio.com}).to_return(status: 400, body: { message: 'Invalid From number' }.to_json)

    expect { described_class.send_message(account, to: '5551234567', body: 'Hi') }
      .to raise_error(described_class::Error, 'Invalid From number')
  end

  it 'sends the invitation SMS and records the event' do
    user = create(:user, account:)
    template = create(:template, account:, author: user)
    submission = create(:submission, :with_submitters, template:, created_by_user: user)
    submitter = submission.submitters.first
    submitter.update!(phone: '+15551234567', preferences: submitter.preferences.merge('send_sms' => true))

    stub = stub_request(:post, %r{api.twilio.com}).to_return(status: 201, body: { sid: 'SM1', num_segments: '1' }.to_json)

    WelloSendSubmitterInvitationSmsJob.new.perform('submitter_id' => submitter.id)

    expect(stub).to have_been_requested
    expect(submitter.reload.sent_at).to be_present
    expect(submitter.submission_events.where(event_type: 'send_sms').count).to eq(1)
  end
end
