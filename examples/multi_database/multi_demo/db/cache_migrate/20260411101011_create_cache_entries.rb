class CreateCacheEntries < ActiveRecord::Migration[8.1]
  def change
    create_table :cache_entries do |t|
      t.string :key

      t.timestamps
    end
  end
end
