module ModelExtensions::Plate
  module NamedScopeHelpers
    def include_plate_named_scope(plate_association)
      named_scope :"include_#{plate_association}", {
        :include => { plate_association.to_sym => ::ModelExtensions::Plate::PLATE_INCLUDES }
      }
    end
  end

  PLATE_INCLUDES = [
    :plate_metadata, {
      :wells => [
        :map,
        :transfer_requests_as_target,
        :uuid_object, {
          :aliquots => [
            :bait_library, {
              :tag => :tag_group,
              :sample => [
                :uuid_object, {
                  :primary_study   => { :study_metadata => :reference_genome },
                  :sample_metadata => :reference_genome
                }
              ]
            }
          ]
        }
      ]
    }
  ]

  def self.included(base)
    base.class_eval do
      named_scope :include_plate_purpose, :include => :plate_purpose
      named_scope :include_wells_with_aliquots, :include => ::ModelExtensions::Plate::PLATE_INCLUDES
    end
  end

  def plate_purpose_or_stock_plate
    self.plate_purpose || PlatePurpose.find_by_name('Stock Plate')
  end

  # Returns a hash from the submission for the pools to the wells that form that pool on this plate.  This is
  # not necessarily efficient but it is correct.
  def pools
    ActiveSupport::OrderedHash.new { |h,k| h[k] = [] }.tap do |pools|
      wells.walk_in_column_major_order do |well, _|
        well.pool_id { |pool_id| pools[pool_id] << well.map.description }
      end
    end
  end
end
