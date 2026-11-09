# frozen_string_literal: true

RSpec.describe 'Wello clients' do
  let(:account) { create(:account) }
  let(:team) { WelloTeam.create!(account:, name: 'Sales') }
  let(:admin) { create(:user, account:, role: User::ADMIN_ROLE) }
  let(:employee) { create(:user, account:, role: User::EMPLOYEE_ROLE, wello_team: team) }
  let(:other_employee) { create(:user, account:, role: User::EMPLOYEE_ROLE) }

  def client_for(user, **attrs)
    WelloClient.create!({ account:, assigned_user: user, dba_name: 'Lux Nails', email: 'owner@luxnails.test',
                          phone: '555-123-4567', merchant_id: '4455667788' }.merge(attrs))
  end

  describe 'directory' do
    it 'lets an employee add a client assigned to themselves' do
      sign_in(employee)

      post wello_clients_path, params: { wello_client: { dba_name: 'Polished Spa', email: 'Hi@Polished.test',
                                                         assigned_user_id: other_employee.id } }

      client = WelloClient.last
      expect(client).to have_attributes(dba_name: 'Polished Spa', email: 'hi@polished.test', assigned_user: employee)
      expect(response).to redirect_to(wello_client_path(client))
    end

    it 'requires a business name' do
      sign_in(employee)

      post wello_clients_path, params: { wello_client: { email: 'x@y.test' } }

      expect(response).to have_http_status(:unprocessable_content)
      expect(WelloClient.count).to eq(0)
    end

    it 'only lists the employee their own clients' do
      mine = client_for(employee, dba_name: 'Mine Nails')
      client_for(other_employee, dba_name: 'Theirs Nails')
      sign_in(employee)

      get wello_clients_path

      expect(response.body).to include(mine.dba_name)
      expect(response.body).not_to include('Theirs Nails')
    end

    it 'lets admins see every client' do
      client_for(employee, dba_name: 'Mine Nails')
      client_for(other_employee, dba_name: 'Theirs Nails')
      sign_in(admin)

      get wello_clients_path

      expect(response.body).to include('Mine Nails', 'Theirs Nails')
    end

    it 'searches by name, MID and phone digits' do
      client_for(admin, dba_name: 'Lux Nails')
      client_for(admin, dba_name: 'Other Spa', merchant_id: '999', phone: '777-000-1111', email: 'o@o.test')
      sign_in(admin)

      get wello_clients_path, params: { q: 'lux' }
      expect(response.body).to include('Lux Nails')
      expect(response.body).not_to include('Other Spa')

      get wello_clients_path, params: { q: '4455667788' }
      expect(response.body).to include('Lux Nails')

      get wello_clients_path, params: { q: '(555) 123' }
      expect(response.body).to include('Lux Nails')
      expect(response.body).not_to include('Other Spa')
    end

    it 'blocks employees from other reps\' client pages' do
      theirs = client_for(other_employee)
      sign_in(employee)

      get wello_client_path(theirs)

      expect(response).to redirect_to(root_path)
    end

    it 'updates a client' do
      client = client_for(employee)
      sign_in(employee)

      patch wello_client_path(client), params: { wello_client: { merchant_id: '123', city: 'Houston' } }

      expect(client.reload).to have_attributes(merchant_id: '123', city: 'Houston')
    end
  end

  describe 'sending a form' do
    let(:template) { create(:template, account:, author: admin, only_field_types: %w[text signature]) }
    let(:client) { client_for(employee, contact_first_name: 'Linh', contact_last_name: 'Tran') }

    before { sign_in(employee) }

    it 'shows the template picker and prefill preview' do
      get new_wello_client_send_form_path(client, template_id: template.id)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include(ERB::Util.html_escape(template.name))
      expect(response.body).to include('First Name')
    end

    it 'creates a submission for the client with prefilled values' do
      expect do
        post wello_client_send_form_path(client), params: { template_id: template.id, send_email: '1', prefill: '1' }
      end.to change(Submission, :count).by(1)

      submission = Submission.last
      submitter = submission.submitters.first

      expect(submission.wello_client_id).to eq(client.id)
      expect(submission.created_by_user).to eq(employee)
      expect(submitter).to have_attributes(email: 'owner@luxnails.test', name: 'Linh Tran')
      expect(submitter.preferences['default_values'].values).to include('Linh')
      expect(response).to redirect_to(wello_client_path(client))
    end

    it 'refuses SMS when Twilio is not configured' do
      post wello_client_send_form_path(client), params: { template_id: template.id, send_sms: '1' }

      expect(response).to have_http_status(:unprocessable_content)
      expect(Submission.count).to eq(0)
    end

    it 'shows sent documents in the client history' do
      post wello_client_send_form_path(client), params: { template_id: template.id, send_email: '1' }

      get wello_client_path(client)

      expect(response.body).to include(ERB::Util.html_escape(template.name))
    end
  end
end
