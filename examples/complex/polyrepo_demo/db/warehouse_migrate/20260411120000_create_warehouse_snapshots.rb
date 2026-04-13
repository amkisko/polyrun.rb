class CreateWarehouseSnapshots < ActiveRecord::Migration[8.1]
  def change
    create_table :warehouse_snapshots do |t|
      t.string :name

      t.timestamps
    end
  end
end
