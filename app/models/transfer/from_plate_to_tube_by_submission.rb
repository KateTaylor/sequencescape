# At the end of the pulldown pipeline the wells of the final plate are transferred, individually,
# into MX library tubes.  Each well is effectively a pool of the stock wells, once they've been
# through the pipeline, so the mapping needs to be based on the original submissions.
class Transfer::FromPlateToTubeBySubmission < Transfer
  class WellToTube < ActiveRecord::Base
    set_table_name('well_to_tube_transfers')

    belongs_to :transfer, :class_name => 'Transfer::FromPlateToTubeBySubmission'
    validates_presence_of :transfer

    belongs_to :destination, :class_name => 'Asset'
    validates_presence_of :destination

    validates_presence_of :source
  end

  include ControlledDestinations

  # Records the transfers from the wells on the plate to the assets they have gone into.
  has_many :well_to_tubes, :class_name => 'Transfer::FromPlateToTubeBySubmission::WellToTube', :foreign_key => :transfer_id

  def transfers
    Hash[well_to_tubes.map { |t| [ t.source, t.destination ] }]
  end

  #--
  # The source plate wells need to be translated back to the stock plate wells, which simply
  # involves following the transfer requests back up until we hit the stock plate.  We only need
  # to follow one transfer request for each well as the submission related stock wells will be in
  # the same final well.  Once we get to the stock well we then find the request that has the 
  # well as a source and the target is an MX library tube.
  #++
  def well_to_destination
    ActiveSupport::OrderedHash[
      locate_stock_wells_for(source).map do |well, stock_wells|
        tube = locate_mx_library_tube_for(stock_wells.first)
        tube.nil? ? nil : [ well, [ tube, stock_wells ] ]
      end.compact
    ]
  end
  private :well_to_destination

  def locate_mx_library_tube_for(stock_well)
    return nil if stock_well.nil?
    stock_well.requests_as_source.detect { |request| request.target_asset.is_a?(MultiplexedLibraryTube) }.try(:target_asset)
  end
  private :locate_mx_library_tube_for

  def record_transfer(source, destination, stock_well)
    @transfers ||= {}
    @transfers[source.map.description] = [ destination, stock_well ]
  end
  private :record_transfer

  after_create :build_well_to_tube_transfers
  def build_well_to_tube_transfers
    tube_to_stock_wells = Hash.new { |h,k| h[k] = [] }
    @transfers.each do |source, (destination, stock_wells)|
      self.well_to_tubes.create!(:source => source, :destination => destination)
      tube_to_stock_wells[destination].concat(stock_wells)
    end

    tube_to_stock_wells.each do |tube, stock_wells|
      tube.update_attributes!(:name => tube_name_for(stock_wells))
    end
  end
  private :build_well_to_tube_transfers

  # Builds the name for the tube based on the wells that are being transferred from by finding their stock plate wells and
  # creating an appropriate range.
  def tube_name_for(stock_wells)
    stock_plates = stock_wells.map(&:plate).uniq
    raise StandardError, "There appears to be no stock plate!" if stock_plates.empty?
    raise StandardError, "Cannot handle cross plate pooling!" if stock_plates.size > 1

    stock_locations, ordered_wells = stock_wells.map(&:map), []
    Map.walk_plate_in_column_major_order(stock_plates.first.size) do |location, _|
      ordered_wells.push(location.description) if stock_locations.include?(location)
    end

    first, last = [ :first, :last ].map(&ordered_wells.compact.method(:send))
    "#{stock_plates.first.sanger_human_barcode} #{first}:#{last}"
  end
  private :tube_name_for
end
