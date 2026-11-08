module.exports = {
  future: {
    hoverOnlyWhenSupported: true
  },
  plugins: [
    require('daisyui')
  ],
  daisyui: {
    themes: [
      {
        docuseal: {
          // Wello Payment brand theme (key kept as "docuseal" so upstream layouts keep working)
          'color-scheme': 'light',
          primary: '#FDE7CC', // soft brand-orange tint for secondary buttons/chips
          'primary-content': '#1F2328',
          secondary: '#F7991F', // Wello orange (logo)
          'secondary-content': '#1F2328',
          accent: '#0E7490', // deep teal accent
          'accent-content': '#FFFFFF',
          neutral: '#1F2328', // charcoal for main buttons and text
          'neutral-content': '#FFFFFF',
          'base-100': '#FFFFFF',
          'base-200': '#F5F6F8',
          'base-300': '#E5E7EB',
          'base-content': '#1F2328',
          '--rounded-btn': '1.9rem',
          '--tab-border': '2px',
          '--tab-radius': '.5rem'
        }
      }
    ]
  }
}
