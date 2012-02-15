class AddIndicesToPlates < ActiveRecord::Migration
  def self.up
      add_index(:plates, :barcode , :name => 'index_plates_on_barcode')
      add_index(:plates, :barcode_prefix_id, :name => 'index_plates_on_barcode_prefix_id')
      add_index(:plates, :legacy_sample_id, :name => 'index_plates_on_sample_id')
      add_index(:plates, :map_id, :name => 'index_plates_on_map_id')
      add_index(:plates, [:sti_type, :updated_at], :name => 'index_plates_on_sti_type_and_updated_at')
      add_index(:plates, :sti_type, :name => 'index_plates_on_sti_type')
      add_index(:plates, :updated_at, :name => 'index_plates_on_updated_at')
  end

  def self.down
  end
end
