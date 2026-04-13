module Types
  class ItemType < Types::BaseObject
    field :id, Integer, null: false
    field :slug, String, null: false
    field :title, String, null: false
  end
end
