const path = require('path')

module.exports = {
  future: {
    hoverOnlyWhenSupported: true
  },
  content: [
    path.resolve(__dirname, 'app/javascript/template_builder/dynamic_area.vue'),
    path.resolve(__dirname, 'app/javascript/template_builder/dynamic_section.vue')
  ],
  theme: {
    extend: {
      colors: {
        'base-100': '#FFFFFF',
        'base-200': '#F5F6F8',
        'base-300': '#E5E7EB',
        'base-content': '#1F2328'
      }
    }
  }
}
