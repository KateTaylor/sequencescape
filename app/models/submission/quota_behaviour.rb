module Submission::QuotaBehaviour

  #after_create :book_quota_available_for_request_types!

  def complete_building
    check_project_details!
    quota_check! unless assets.blank?
    super
  end

  def multiplier_for(request_type)
    return 1 if self.request_options.blank? or not self.request_options.key?(:multiplier)
    self.request_options[:multiplier][request_type.id.to_i] || 1
  end
  private :multiplier_for

  def quota_check!
    return unless project.enforce_quotas?
    check_project_details!
    #check_quota_available_for_request_types!
    # not needed anymore as quota are book at creation time
    # and quota are checked when creating request
  end
  private :quota_check!

  def check_project_details!
    raise QuotaException, "Quotas are being enforced but have not been setup"       if project.quotas.all.empty?
    raise QuotaException, "Project #{project.name} is not approved"                 unless project.approved?
    raise QuotaException, "Project #{project.name} is not active"                   unless project.active?
    raise QuotaException, "Project #{project.name} does not have a budget division" unless project.actionable?
  end
  private :check_project_details!

  def book_quota_available_for_request_types!
    Order.transaction do
      request_type_records = RequestType.find(self.request_types)
      multiplexed          = !request_type_records.detect(&:for_multiplexing?).nil?
      request_type_records.each do |request_type|
        # If the user requires multiple runs of this request type then we need to count for that in the quota.
        # If we're not multiplexing in general, or for this individual request type, then we have to have enough
        # quote for all of the assets.  Otherwise they can be considered to be a single asset (i.e. a pool of them)
        quota_required  = multiplier_for(request_type)
        quota_required *= assets.size if not multiplexed or request_type.for_multiplexing?
        book_quota(request_type, quota_required)
      end
    end
  end
  private :book_quota_available_for_request_types!

  def use_quota!(request, unbook=true)
    return unless project
    project.quota_for!(request.request_type_id).add_request!(request,unbook)
  end

  delegate :book_quota, :unbook_quota, :quota_for!, :to => :project
  def self.included(base)
    base.class_eval do
      after_create :book_quota_available_for_request_types!
    end
  end
end
