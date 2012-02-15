class AddIndicesToFragments < ActiveRecord::Migration
  def self.up
      add_index(:fragments, :barcode , :name => 'index_fragments_on_barcode')
      add_index(:fragments, :barcode_prefix_id, :name => 'index_fragments_on_barcode_prefix_id')
      add_index(:fragments, :legacy_sample_id, :name => 'index_fragments_on_sample_id')
      add_index(:fragments, :map_id, :name => 'index_fragments_on_map_id')
      add_index(:fragments, [:sti_type, :updated_at], :name => 'index_fragments_on_sti_type_and_updated_at')
      add_index(:fragments, :sti_type, :name => 'index_fragments_on_sti_type')
      add_index(:fragments, :updated_at, :name => 'index_fragments_on_updated_at')
  end

  def self.down
  end
end
