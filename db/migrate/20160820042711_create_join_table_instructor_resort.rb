class CreateJoinTableInstructorResort < ActiveRecord::Migration
  def change
    create_join_table :instructors, :resorts do |t|
      # t.index [:instructor_id, :resort_id]
      # t.index [:resort_id, :instructor_id]
    end
  end
end
