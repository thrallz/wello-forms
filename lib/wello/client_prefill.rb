# frozen_string_literal: true

module Wello
  # Fills a template's text fields from a client record when the field name matches
  # a known label (e.g. a field named "DBA" or "Merchant ID").
  module ClientPrefill
    FIELD_TYPES = %w[text cells].freeze

    NAME_MAP = {
      dba_name: ['business name', 'dba', 'dba name', 'doing business as', 'merchant name', 'company',
                 'company name', 'business', 'store name', 'salon name'],
      legal_name: ['legal name', 'legal business name', 'business legal name', 'corporate name', 'entity name'],
      contact_name: ['name', 'full name', 'contact name', 'contact', 'owner name', 'owner', 'signer name',
                     'principal name', 'authorized signer'],
      contact_first_name: ['first name', 'owner first name', 'contact first name'],
      contact_last_name: ['last name', 'owner last name', 'contact last name'],
      email: ['email', 'e mail', 'email address', 'business email', 'owner email', 'contact email'],
      phone: ['phone', 'phone number', 'business phone', 'telephone', 'mobile', 'cell', 'contact phone'],
      merchant_id: ['mid', 'merchant id', 'merchant number', 'merchant id number', 'merchant'],
      address_line1: ['address', 'street', 'street address', 'business address', 'address line 1', 'address 1'],
      address_line2: ['address line 2', 'address 2', 'suite', 'unit', 'suite unit'],
      city: ['city', 'business city'],
      state: ['state', 'business state'],
      zip: ['zip', 'zip code', 'zipcode', 'postal code', 'business zip'],
      full_address: ['full address', 'complete address', 'business full address']
    }.freeze

    LOOKUP = NAME_MAP.each_with_object({}) do |(attr, names), acc|
      names.each { |name| acc[name] = attr }
    end.freeze

    module_function

    def normalize(name)
      name.to_s.downcase.gsub(/[^a-z0-9]+/, ' ').squish
    end

    def value_for(client, attr)
      case attr
      when :contact_name then client.contact_name
      when :full_address then client.address_lines.join(', ')
      else client.public_send(attr)
      end
    end

    # Returns { field_name => value } for the given template submitter (role) uuid.
    def values(client, template, submitter_uuid)
      template.fields.each_with_object({}) do |field, acc|
        next if field['submitter_uuid'] != submitter_uuid
        next unless FIELD_TYPES.include?(field['type'])
        next if field['name'].blank?

        attr = LOOKUP[normalize(field['name'])]
        value = attr && value_for(client, attr)

        acc[field['name']] = value if value.present?
      end
    end
  end
end
