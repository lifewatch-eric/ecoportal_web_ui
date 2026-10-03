# frozen_string_literal: true

Rails.application.config.after_initialize do
  next unless $SITE.to_s.casecmp?('EcoPortal')

  $SUPPORT_EMAIL = 'semantics@lifewatch.eu'
  $ENABLE_SLICES = false
  $HOME_PAGE_LOGOS = [
    { img_src: 'logos/supports/LW_ITA.png', url: 'https://www.lifewatch.eu', target: '_blank' },
    { img_src: 'logos/supports/eu.png', url: 'https://commission.europa.eu/research-and-innovation_en', target: '_blank' },
    { img_src: 'logos/supports/cnr.png', url: 'https://www.cnr.it/en', target: '_blank' },
    { img_src: 'logos/collaboration/inrae.png', url: 'https://www.inrae.fr/enm', target: '_blank' },
    { img_src: 'logos/collaboration/stanford.png', url: 'https://www.stanford.edu', target: '_blank' }
  ]

  $FOOTER_LINKS[:social].each do |link|
    link[:link] = "mailto:#{$SUPPORT_EMAIL}" if link[:logo] == 'social/email.svg'
  end
  $FOOTER_LINKS[:sections][:agreements][:terms] = 'https://www.lifewatch.eu/terms-and-conditions/'
end
