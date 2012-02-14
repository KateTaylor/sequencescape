class MakeAssetView < ActiveRecord::Migration
  # recreate assets from the three databae tables to support named_scopes with the abstract assets class
  def self.up
    connection.execute("create view assets as select * from fragments union select * from plates union select * from aliquot_receptacles;")
  end

  def self.down
    connection.execute("drop view assets;")
  end
end
