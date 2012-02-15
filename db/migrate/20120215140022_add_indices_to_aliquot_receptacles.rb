class AddIndicesToAliquotReceptacles < ActiveRecord::Migration
  def self.up
      add_index(:aliquot_receptacles, :barcode , :name => 'index_aliquot_receptacles_on_barcode')
      add_index(:aliquot_receptacles, :barcode_prefix_id, :name => 'index_aliquot_receptacles_on_barcode_prefix_id')
      add_index(:aliquot_receptacles, :legacy_sample_id, :name => 'index_aliquot_receptacles_on_sample_id')
      add_index(:aliquot_receptacles, :map_id, :name => 'index_aliquot_receptacles_on_map_id')
      add_index(:aliquot_receptacles, [:sti_type, :updated_at], :name => 'index_aliquot_receptacles_on_sti_type_and_updated_at')
      add_index(:aliquot_receptacles, :sti_type, :name => 'index_aliquot_receptacles_on_sti_type')
      add_index(:aliquot_receptacles, :updated_at, :name => 'index_aliquot_receptacles_on_updated_at')
  end

  def self.down
  end
end
