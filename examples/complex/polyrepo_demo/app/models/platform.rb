# Demo “super-platform” verticals: each maps to a business domain for docs + coverage examples.
module Platform
  VERTICALS = %w[banking clinic library ledger blog forum assistant analytics].freeze

  LABELS = {
    "banking" => "Retail Banking",
    "clinic" => "Clinical & Pharmacy",
    "library" => "Lending & Catalog",
    "ledger" => "Accounting & GL",
    "blog" => "Content & CMS",
    "forum" => "Community & Moderation",
    "assistant" => "Diary & Chatbot",
    "analytics" => "Charts & BI"
  }.freeze

  module_function

  def label_for(slug)
    LABELS[slug.to_s] || slug.to_s.titleize
  end
end
