class CreateDefectTrendByWeeks < ActiveRecord::Migration
  def change
    create_table :defect_trend_by_weeks do |t|
      t.date :day
      t.integer :created
      t.integer :closed
      t.integer :fixed
      t.integer :wsi

      t.timestamps null: false
    end
  end
end
