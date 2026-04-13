module Types
  CatalogRow = Data.define(:id, :slug, :title)

  class QueryType < Types::BaseObject
    field :health, String, null: false, description: "Liveness string for GraphQL clients"
    field :verticals, [String], null: false, description: "Business domains (banking, clinic, …)"
    field :items, [Types::ItemType], null: false
    field :item, Types::ItemType, null: true, description: "One catalog row by slug (same as REST /api/v1/items/:slug)" do
      argument :slug, String, required: true
    end

    def health
      "ok"
    end

    def verticals
      Platform::VERTICALS
    end

    def items
      Catalog.items.map { |h| CatalogRow.new(**h) }
    end

    def item(slug:)
      row = Catalog.find_by_slug(slug)
      row ? CatalogRow.new(**row) : nil
    end
  end
end
