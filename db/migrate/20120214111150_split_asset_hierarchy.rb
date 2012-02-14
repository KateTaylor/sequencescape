class SplitAssetHierarchy < ActiveRecord::Migration
  def self.up
    ActiveRecord::Base.transaction do
      say 'Splitting up the assets table into aliquot_receptacles...'
      connection.execute("drop table if exists aliquot_receptacles;")
      connection.execute("create table aliquot_receptacles as 
        select * from assets where sti_type in 
('LibraryTube', 'MultiplexedLibraryTube', 'PacBioLibraryTube', 'PulldownMultiplexedLibraryTube', 'SampleTube', ' StockLibraryTube', 'StockMultiplexedLibraryTube',
          'Lane', 'Well');")
      say 'Done.'

      say 'Splitting up the assets table into fragments...'
      connection.execute("drop table if exists fragments;")
      connection.execute("create table fragments as select * from assets where sti_type = 'Fragment';")
      say 'Done.'

      say 'Splitting up the assets table into plates...'
      connection.execute("drop table if exists plates;")
      connection.execute("create table plates as 
        select * from assets where sti_type in 
('ControlPlate','GelDilutionPlate','PicoAssayAPlate','PicoAssayBPlate','PicoDilutionPlate','Plate','PlateTemplate','SequenomQcPlate','WorkingDilutionPlate');")
      say 'Done.'

      say 'Hiding the assets table as hidden_assets...'
      connection.execute("rename table assets to hidden_assets;")
      say 'Done.'
    end
  end

  def self.down
    ActiveRecord::Base.transaction do
      say 'Dropping table aliquot_receptacles...'
      connection.execute("drop table aliquot_receptacles;")
      say 'Done.'

      say 'Dropping table fragments...'
      connection.execute("drop table fragments;")
      say 'Done.'

      say 'Dropping table plates...'
      connection.execute("drop table plates;")
      say 'Done.'

      say 'Revealing the assets table from hidden_assets...'
      connection.execute("rename table hidden_assets to assets;")
      say 'Done.'
    end
  end
end

