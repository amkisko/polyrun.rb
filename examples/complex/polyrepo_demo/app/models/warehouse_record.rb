# Third SQLite database — analytics / warehouse slice (parallel CI uses distinct paths per shard).
class WarehouseRecord < ActiveRecord::Base
  self.abstract_class = true

  connects_to database: {writing: :warehouse, reading: :warehouse}
end
