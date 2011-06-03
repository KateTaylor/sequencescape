class AssetsController < ApplicationController
  include BarcodePrintersController::Print
   before_filter :discover_asset, :only => [:show, :edit, :update, :destory, :summary, :close, :print_assets, :print, :show_plate, :create_wells_group, :history, :holded_assets, :complete_move_to_2D]

  def index
    @assets_without_requests = []
    @assets_with_requests = []
    if params[:study_id]
      @study = Study.find(params[:study_id])
      @assets_with_requests = @study.assets.paginate :page => params[:page], :order => 'created_at DESC'
      assets = []
      @study.asset_groups.each{|ag| assets << ag.assets }
      assets.flatten!
      @assets = assets # for print
      @assets_without_requests = assets - @assets_with_requests
    end

    respond_to do |format|
      if params[:print]
        format.html { render :action => :print_index }
      else
        format.html
      end
      if params[:study_id]
        format.xml  { render :xml => Study.find(params[:study_id]).assets.to_xml }
      elsif params[:sample_id]
          format.xml  { render :xml => Sample.find(params[:sample_id]).assets.to_xml }
      elsif params[:asset_id]
        @asset = Asset.find(params[:asset_id])
        format.xml  { render :xml => ["relations" => {"parents" => @asset.parents, "children" => @asset.children}].to_xml }
      end
    end
  end
  
  def show
    respond_to do |format|
      format.html
      format.xml
      format.json { render :json => @asset }
    end
  end

  def new
    @asset = Asset.new
		@asset_types = { "Sample Tube" =>'SampleTube', "Library Tube" => 'LibraryTube', "Hybridization Buffer Spiked" => "SpikedBuffer" }

    respond_to do |format|
      format.html
      format.xml  { render :xml => @asset }
    end
  end

  def edit
  end

  def find_parents(text)
    return [] unless text.present?
      names = text.lines.map(&:chomp).reject { |l| l.blank? }
      objects = Asset.find(:all, :conditions => {:id => names})
      objects += Asset.find(:all, :conditions => {:barcode => names})
      name_set = Set.new(names)
      found_set = Set.new(objects.map(&:name))
      not_found = name_set - found_set
      raise InvalidInputException, "#{Asset.table_name} #{not_found.to_a.join(", ")} not founds" unless not_found.empty?
      return objects
  end

  def create
    count = first_param(:count)
    count = count.present? ? count.to_i : 1
    saved = true

    begin
      Asset.transaction do
        @assets = []
        sti_type = params[:asset].delete(:sti_type)
        asset_class = sti_type.present? ?  sti_type.constantize : Asset
        1.upto(count) do |n|
          asset = asset_class.new(params[:asset]) do |asset|
            asset.name += " ##{n}" if count !=1
          end

          # from asset
          parent_param = first_param(:parent_asset)
          if parent_param.present?
            parent = Asset.find_by_id(parent_param) || Asset.find_from_machine_barcode(parent_param) || Asset.find_by_name(parent_param)
            if parent.present?
              parent_volume = params[:parent_volume]
              if parent_volume.present? and parent_volume.first.present?
                extract= parent.transfer(parent_volume.first)

                if asset.volume
                  parent = extract

                  # We must copy the aliquots of the 'extract' to the asset, otherwise the asset remains
                  # empty.
                  asset.save!
                  asset.aliquots = parent.aliquots.map(&:clone)
                elsif asset.is_a?(SpikedBuffer) and !parent.is_a?(SpikedBuffer)
                  # error should have its own volume
                  flash[:error] = "Enter a volume"
                  saved = false
                  break
                else # 
                  # Discard the 'asset' that was build initially as it is being replaced by the asset
                  # created from the extraction process.
                  extract.update_attributes!(:name => asset.name)
                  asset = extract
                  parent = nil
                end
              end

              asset.add_parent(parent)
            end
          else
            # We must save the asset now because the parent stuff isn't being executed.
            asset.save!
          end
          #Study
          
          asset.update_attributes!(:barcode => AssetBarcode.new_barcode) if asset.barcode.nil?
           
          #TODO : add request or an event
          asset.comments << Comment.new(:user => current_user, :description => "asset has been created by #{current_user.login}")

          # Can't add the sample until after the asset has been created, and then only if it doesn't
          # already have any aliquots in it.
          sample_param = params[:sample]
          sample = Sample.find_by_id(sample_param) || Sample.find_by_name(sample_param)
          if sample.present?
            raise StandardError, "Asset already has aliquots in it" unless asset.aliquots.empty?
            asset.aliquots.create!(:sample => sample)
          end

          # associate tag 
          # create a new tag instance or assign the tag is it's a tag instance
          tag_param = first_param(:tag)
          if tag_param.present?
            tag = nil
            oligo = params[:tag_sequence]
            if oligo.present? && oligo.first.present?
              oligo = oligo.first.upcase!
              tag = Tag.find(:first, :conditions => {:map_id => tag_param, :oligo => oligo })
            else
              tags = Tag.find_all_by_map_id(tag_param)
              if tags.size ==1
                tag = tags.first
              end

            end
            unless tag
              flash[:error] = "Tag #{tag_param}:#{params[:tag_sequence]} not found"
              saved = false
            end

            asset.attach_tag(tag)
          end

          @assets << asset
        end
      end # transaction
    rescue Asset::VolumeError => ex
      saved = false
      flash[:error] = ex.message
    rescue => exception
      saved = false
      flash[:error] = exception.message
    end

    respond_to do |format|
      if saved
        flash[:notice] = 'Asset was successfully created.'
        format.html { render :action => :create}
        format.xml  { render :xml => @assets, :status => :created, :location => assets_url(@assets) }
        format.json { render :json => @assets, :status => :created, :location => assets_url(@assets) }
      else
        format.html { redirect_to :action => "new" }
        format.xml  { render :xml => @assets.errors, :status => :unprocessable_entity }
        format.json { render :json => @assets.errors, :status => :unprocessable_entity }
      end
    end
  end

  def history
    respond_to do |format|
      format.html
      format.xml  { @request.events.to_xml }
      format.json { @request.events.to_json }
    end
  end

  def update
    respond_to do |format|
      if (@asset.update_attributes(params[:asset]) &&  @asset.update_attributes(params[:lane]))
        flash[:notice] = 'Asset was successfully updated.'
        unless params[:lab_view]
          format.html { redirect_to(:action => :show, :id => @asset.id) }
          format.xml  { head :ok }
        else
          format.html { redirect_to(:action => :lab_view, :barcode => @asset.barcode) }
        end
      else
        format.html { render :action => "edit" }
        format.xml  { render :xml => @asset.errors, :status => :unprocessable_entity }
      end
    end
  end

  def destroy
    @asset.destroy

    respond_to do |format|
      format.html { redirect_to(assets_url) }
      format.xml  { head :ok }
    end
  end

  def summary
    @summary = UiHelper::Summary.new({:per_page => 25, :page => params[:page]})
    @summary.load_item(@asset)
  end

  def close
    @asset.closed = !@asset.closed
    @asset.save
    respond_to do |format|
      if  @asset.closed
        flash[:notice] = "Asset #{@asset.name} was closed."
      else
        flash[:notice] = "Asset #{@asset.name} was opened."
      end
      format.html { redirect_to(asset_url(@asset)) }
      format.xml  { head :ok }
    end
  end

  def print_labels
    print_asset_labels(new_asset_url, new_asset_url)
  end

  def print_assets
    printables = []
    printables.push PrintBarcode::Label.new({ :number => @asset.barcode, :study => "#{@asset.barcode}_#{@asset.name.gsub("_", " ")}", :suffix => "" })
    unless printables.empty?
      BarcodePrinter.print(printables, params[:printer])
    end

    flash[:notice] = "Your labels have been sent to printer #{params[:printer]}."
    redirect_to asset_url(@asset)
  rescue SOAP::FaultError
    flash[:warning] = "There is a problem with the selected printer. Please report it to Systems."
    redirect_to asset_url(@asset)
  end
  def submit_wells
    @asset = Asset.find params[:id]
  end

  def show_plate
  end

  before_filter :prepare_asset, :only => [ :new_request, :create_request ]

  def prepare_asset
    @asset = Asset.find(params[:id])
  end
  private :prepare_asset

  def new_request_for_current_asset
    new_request_asset_path(@asset, {:study_id => @study.id, :project_id => params[:project_id], :request_type_id => @request_type.id})
  end
  private :new_request_for_current_asset

  def new_request
    @request_types = RequestType.applicable_for_asset(@asset)
  end

  def create_request
    @request_type = RequestType.find(params[:request_type_id])
    @study        = Study.find(params[:study_id])

    request_options = params.fetch(:request, {}).fetch(:request_metadata_attributes, {})
    request_options[:multiplier] = { @request_type.id => params[:count].to_i } unless params[:count].blank?
    submission = ReRequestSubmission.build!(
      :study           => @study,
      :project         => Project.find(params[:project_id]),
      :workflow        => @request_type.workflow,
      :user            => current_user,
      :assets          => [ @asset ],
      :request_types   => [ @request_type.id ],
      :request_options => request_options,
      :comments        => params[:comments]
    )

    respond_to do |format| 
      flash[:notice] = 'Created request'

      format.html { redirect_to new_request_for_current_asset }
      format.json { render :json => submission.requests, :status => :created }
    end
  rescue QuotaException => exception
    respond_to do |format|
      flash[:error] = exception.message
      format.html { redirect_to new_request_for_current_asset }
      format.json { render :json => exception.message, :status => :unprocessable_entity }
    end
  rescue ActiveRecord::RecordNotFound => exception
    respond_to do |format|
      flash[:error] = exception.message
      format.html { redirect_to new_request_for_current_asset }
      format.json { render :json => exception.message, :status => :precondition_failed }
    end
  rescue ActiveRecord::RecordInvalid => exception 
    respond_to do |format|
      flash[:error] = exception.message
      format.html { redirect_to new_request_for_current_asset }
      format.json { render :json => exception.message, :status => :precondition_failed }
    end
  end

  def create_wells_group
    study_id = params[:asset_group][:study_id]

    if study_id.blank?
      flash[:error] = "Please select a study"
      redirect_to submit_wells_asset_path(@asset)
      return
    end

    asset_group = @asset.create_asset_group_wells(@current_user, params[:asset_group])
    redirect_to template_chooser_study_workflow_submissions_path(nil, asset_group.study, @current_user.workflow)
  end

  def get_barcode
    barcode = Asset.get_barcode_from_params(params)
    render(:text => "#{Barcode.barcode_to_human(barcode)} => #{barcode}")
  end

  def lookup
    if params[:asset] && params[:asset][:barcode]
      id = params[:asset][:barcode][3,7].to_i
      @assets = Asset.find(:all, :conditions => {:barcode => id}).paginate :per_page => 50, :page => params[:page]

      if @assets.size == 1
        @asset = @assets.first
        respond_to do |format|
          format.html { render :action => "show" }
          format.xml  { render :xml => @assets.to_xml }
        end
      elsif @assets.size == 0
        if params[:asset] && params[:asset][:barcode]
          flash[:error] = "No asset found with barcode #{params[:asset][:barcode]}"
        end
        respond_to do |format|
          format.html { render :action => "lookup" }
          format.xml  { render :xml => @assets.to_xml }
        end
      else
        respond_to do |format|
          format.html { render :action => "index" }
          format.xml  { render :xml => @assets.to_xml }
        end
      end
    end
  end

  def filtered_move
    @asset = Asset.find(params[:id])
    if @asset.resource
      @studies = []
      @studies_from = []
      flash[:error] = "This Asset is Control Lane."
    else
      @studies = Study.all
      @studies.each do |study|
        study.name = study.name + " (" + study.id.to_s + ")"
      end
      if (@asset.is_a?(Plate) || @asset.is_a?(Well))
        @studies_from = @asset.studies
      else  
        @studies_from = @asset.studies_list
      end
      @studies_from.each do |study|
        study.name = study.name + " (" + study.id.to_s + ")"
      end
    end
  end

  def select_asset_name_for_move
    @asset = Asset.find(params[:asset_id])
    study = Study.find_by_id(params[:study_id_to])
    @assets = []
    unless study.nil?
      @assets = study.asset_groups
    end
    render :layout => false
  end

  def reset_values_for_move
    render :layout => false
  end

  def move_single(params)
    @asset          = Asset.find(params[:id])
    @study_from     = Study.find(params[:study_id_from])
    @study_to       = Study.find(params[:study_id_to])
    @asset_group    = AssetGroup.find_by_id(params[:asset_group_id])
    if @asset_group.nil?
      @asset_group    = AssetGroup.find_or_create_asset_group(params[:new_assets_name], @study_to)
    end

    result = @asset.move_to_asset_group(@study_from, @study_to, @asset_group, params[:new_assets_name], current_user)
    return result
  end

  def move
    @asset = Asset.find(params[:id])
    unless check_valid_values(params)
      redirect_to :action => :filtered_move, :id => params[:id]
      return
    end
    
    result = move_single(params)
    if result
      flash[:notice] = "Assets has been moved"
      redirect_to asset_path(@asset)
    else
      flash[:error] = @asset.errors.full_messages.join("<br />")
      redirect_to :action => "filtered_move", :id => @asset.id
    end
  end
  
  def find_by_barcode
  end
  
  def lab_view
    barcode = params[:barcode]
    if barcode.blank?
      redirect_to :action => "find_by_barcode"
    else
      if barcode.size == 13 && Barcode.check_EAN(barcode)
        @asset = Asset.find_by_barcode(Barcode.split_barcode(barcode)[1])
      else
        @asset = Asset.find_by_barcode(barcode)
      end
      
      if @asset.nil?
        flash[:error] = "Unable to find anything with this barcode"
        redirect_to :action => "find_by_barcode"
      end
    end
  end
  
  def create_stocks
    params[:assets].each do |id, params|
      asset = Asset.find(id)
      unless asset.nil?
        stock_asset = asset.create_stock_asset!(
          :name          => params[:name],
          :volume        => params[:volume],
          :concentration => params[:concentration]
        )
        
        stock_asset.assign_relationships(asset.parents, asset)
      end
    end
    
    batch = Batch.find(params[:batch_id])
    redirect_to batch_path(batch)
  end

  def move_requests(source_asset, destination_asset)
    @pipeline = Pipeline.find(1)
    request_type = @pipeline.request_type
    request = Request.find_by_asset_id_and_request_type_id_and_state(source_asset.id, request_type.id, "pending")
    unless request.nil?
      # make the event
      self.events << Event.new({:message => "Moved from 1D tube #{source_asset.id} to 2D tube #{destination_asset.id}", :created_by => user.login, :family => "Update"})
      # Move all requests
      self.requests.each do |request|
        request.events << Event.new({:message => "Moved from 1D tube #{source_asset.id} to 2D tube #{destination_asset.id}", :created_by => user.login, :family => "Update"})
        request.study_id = study.id
      end
    end
  end

  private
  def discover_asset
    @asset = Asset.find(params[:id], :include => { :requests => :request_metadata })
  end

  def check_valid_values(params = nil)
    if (params[:study_id_to] == "0") || (params[:study_id_from] == "0")
      flash[:error] = "You have to select 'Study From' and 'Study To'"
      return false
    else
      study_from = Study.find(params[:study_id_from])
      study_to = Study.find(params[:study_id_to])
      if study_to.name.eql?(study_from.name)
        flash[:error] = "You can't select the same Study."
        return false
      elsif params[:asset_group_id] == "0" && params[:new_assets_name].empty?
        flash[:error] = "You must indicate an 'Asset Group'."
        return false
      elsif !(params[:asset_group_id] == "0") && !(params[:new_assets_name].empty?)
        flash[:error] = "You can select only an Asset Group!"
        return false
      elsif AssetGroup.find_by_name(params[:new_assets_name])
        flash[:error] = "The name of Asset Group exists!"
        return false
      end
    end
    return true
  end

end
