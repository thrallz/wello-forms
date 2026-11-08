# frozen_string_literal: true

# Wello Forms branding. Docuseal.product_name is intentionally left as "DocuSeal"
# because it powers the required DocuSeal attribution (see LICENSE_ADDITIONAL_TERMS).
module Wello
  BRAND_NAME = ENV.fetch('WELLO_BRAND_NAME', 'Wello Forms')
  COMPANY_NAME = 'Wello Payment'
  LOGO_PATH = '/wello/wello-payment-logo-sm.png'
  ICON_PATH = '/wello/wello-payment-icon-sm.png'

  COLORS = {
    orange: '#F7991F',
    orange_dark: '#B45309',
    charcoal: '#1F2328',
    teal: '#0E7490'
  }.freeze

  module_function

  def brand_name
    BRAND_NAME
  end
end
