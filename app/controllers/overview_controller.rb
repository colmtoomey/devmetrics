class OverviewController < ApplicationController
  
  def index
  	@weeks=DefectTrendByWeek.all.order(day: :asc)
  end

  def group
  	@weeks=DefectTrendByWeek.all.order(day: :asc)
  end

	#user = User.find_by(name: 'David')

	#defect_record=DefectTrendByWeek.create(day: theday, created: created_wsi, closed: closed_wsi, fixed: fixed_wsi, wsi: the_wsi);

	#d.save
  #end
end
