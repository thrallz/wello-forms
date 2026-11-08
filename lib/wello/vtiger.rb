# frozen_string_literal: true

require 'net/http'

module Wello
  # Vtiger Cloud REST API (https://<instance>.odX.vtiger.com/restapi/v1/vtiger/default)
  # with HTTP Basic auth (username + access key from Vtiger → My Preferences).
  module Vtiger
    CONFIG_KEY = 'wello_vtiger'
    API_PATH = '/restapi/v1/vtiger/default'
    SUPPORTED_MODULES = %w[Accounts Contacts Leads Potentials].freeze

    Error = Class.new(StandardError)

    module_function

    def config(account)
      value = EncryptedConfig.find_by(account:, key: CONFIG_KEY)&.value

      value.is_a?(Hash) ? value : {}
    end

    def configured?(account)
      c = config(account)

      c['url'].present? && c['username'].present? && c['access_key'].present?
    end

    def request(account, operation, params = {}, method: :get, vtiger_config: nil)
      c = vtiger_config || config(account)

      raise Error, 'Vtiger is not configured' if c['url'].blank? || c['username'].blank? || c['access_key'].blank?

      uri = URI.join(base_url(c['url']), "#{API_PATH}/#{operation}")

      http_request =
        if method == :post
          Net::HTTP::Post.new(uri).tap { |r| r.set_form_data(params) }
        else
          uri.query = URI.encode_www_form(params) if params.present?
          Net::HTTP::Get.new(uri)
        end

      http_request.basic_auth(c['username'], c['access_key'])
      http_request['Accept'] = 'application/json'

      response = Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == 'https',
                                                     open_timeout: 10, read_timeout: 20) do |http|
        http.request(http_request)
      end

      parse_response(response)
    rescue SocketError, Net::OpenTimeout, Net::ReadTimeout, Errno::ECONNREFUSED, JSON::ParserError => e
      raise Error, "Vtiger connection failed: #{e.message}"
    end

    def parse_response(response)
      data = JSON.parse(response.body.presence || '{}')

      if !response.is_a?(Net::HTTPSuccess) || data['success'] == false
        message = data.dig('error', 'message').presence || "Vtiger error #{response.code}"

        raise Error, message
      end

      data['result']
    end

    def base_url(url)
      url = url.to_s.strip
      url = "https://#{url}" unless url.match?(%r{\Ahttps?://}i)

      uri = URI(url)

      "#{uri.scheme}://#{uri.host}#{":#{uri.port}" if uri.port && [80, 443].exclude?(uri.port)}"
    end

    def me(account, vtiger_config: nil)
      request(account, 'me', vtiger_config:)
    end

    def retrieve(account, webservice_id)
      request(account, 'retrieve', { id: webservice_id })
    end

    # Converts a plain CRM record id (what VTAP.Detail.Id() returns) into a webservice id like "11x123".
    def webservice_id(account, module_name, record_id)
      record_id = record_id.to_s.strip

      return record_id if record_id.match?(/\A\d+x\d+\z/)
      raise Error, 'Invalid Vtiger record id' unless record_id.match?(/\A\d+\z/)

      prefix = Rails.cache.fetch("wello_vtiger_prefix:#{account.id}:#{module_name}", expires_in: 1.day) do
        request(account, 'describe', { elementType: module_name })['idPrefix']
      end

      raise Error, "Unknown Vtiger module #{module_name}" if prefix.blank?

      "#{prefix}x#{record_id}"
    end

    # Maps a Vtiger record to Wello client attributes.
    # Deals and contacts that belong to an organization are filed under that organization.
    def client_attributes(account, module_name, record)
      c = config(account)
      mid_field = c['mid_field'].presence

      attrs =
        case module_name
        when 'Accounts' then account_attributes(record)
        when 'Contacts' then contact_attributes(account, record)
        when 'Leads' then lead_attributes(record)
        when 'Potentials' then deal_attributes(account, record)
        else raise Error, "Unsupported Vtiger module #{module_name}"
        end

      attrs[:merchant_id] = record[mid_field] if mid_field && record[mid_field].present?

      attrs.compact_blank
    end

    def account_attributes(record)
      {
        vtiger_module: 'Accounts', vtiger_id: record['id'],
        dba_name: record['accountname'], email: record['email1'].presence || record['email2'],
        phone: record['phone'].presence || record['otherphone'],
        address_line1: record['bill_street'], city: record['bill_city'], state: record['bill_state'],
        zip: record['bill_code']
      }
    end

    def contact_attributes(account, record)
      attrs = {
        vtiger_module: 'Contacts', vtiger_id: record['id'],
        contact_first_name: record['firstname'], contact_last_name: record['lastname'],
        email: record['email'], phone: record['mobile'].presence || record['phone'],
        address_line1: record['mailingstreet'], city: record['mailingcity'], state: record['mailingstate'],
        zip: record['mailingzip']
      }

      organization = related_record(account, record['account_id'])

      unless organization
        return attrs.merge(dba_name: [attrs[:contact_first_name], attrs[:contact_last_name]].compact_blank.join(' '))
      end

      account_attributes(organization)
        .merge(attrs.slice(:contact_first_name, :contact_last_name, :email, :phone).compact_blank)
    end

    def lead_attributes(record)
      {
        vtiger_module: 'Leads', vtiger_id: record['id'],
        dba_name: record['company'], contact_first_name: record['firstname'], contact_last_name: record['lastname'],
        email: record['email'], phone: record['mobile'].presence || record['phone'],
        address_line1: record['lane'], city: record['city'], state: record['state'], zip: record['code']
      }
    end

    def deal_attributes(account, record)
      organization = related_record(account, record['related_to'])
      contact = related_record(account, record['contact_id'])

      raise Error, 'This deal is not linked to an organization or contact' if organization.nil? && contact.nil?

      attrs = organization ? account_attributes(organization) : contact_attributes(account, contact)

      if contact && organization
        attrs = attrs.merge(contact_first_name: contact['firstname'], contact_last_name: contact['lastname'])
        attrs[:email] = contact['email'] if attrs[:email].blank?
        attrs[:phone] = contact['mobile'].presence || contact['phone'] if attrs[:phone].blank?
      end

      attrs
    end

    def related_record(account, value)
      id = value.is_a?(Hash) ? value['value'] || value['id'] : value

      return if id.blank? || !id.to_s.match?(/\A\d+x\d+\z/)

      retrieve(account, id)
    end

    # Finds (or builds) the Wello client for a Vtiger record with fresh details from Vtiger. Not saved.
    def build_client(account:, user:, module_name:, record_id:)
      raise Error, "Unsupported Vtiger module #{module_name}" unless SUPPORTED_MODULES.include?(module_name)

      ws_id = webservice_id(account, module_name, record_id)
      attrs = client_attributes(account, module_name, retrieve(account, ws_id))

      client = WelloClient.find_by(account:, vtiger_id: attrs[:vtiger_id])
      client ||= WelloClient.active.find_by(account:, vtiger_id: nil, email: attrs[:email]) if attrs[:email].present?
      client ||= WelloClient.new(account:, assigned_user: user)

      client.assign_attributes(attrs)

      client
    end

    def sync_client(client)
      raise Error, 'This client is not linked to Vtiger' if client.vtiger_id.blank?

      record = retrieve(client.account, client.vtiger_id)

      client.update!(client_attributes(client.account, client.vtiger_module.presence || 'Accounts', record))

      client
    end

    def enqueue_completed_note(submission)
      client = submission.wello_client

      return if client&.vtiger_id.blank?
      return unless configured?(submission.account)

      WelloVtigerCompletedNoteJob.perform_async('submission_id' => submission.id)
    end

    def add_comment(account, related_to:, text:)
      owner_id = me(account)['id']

      request(account, 'create', {
                elementType: 'ModComments',
                element: { commentcontent: text, related_to:, assigned_user_id: owner_id }.to_json
              }, method: :post)
    end
  end
end
