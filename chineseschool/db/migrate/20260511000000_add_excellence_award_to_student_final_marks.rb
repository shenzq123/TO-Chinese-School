class AddExcellenceAwardToStudentFinalMarks < ActiveRecord::Migration
  def change
    add_column :student_final_marks, :excellence_award, :boolean, default: false, null: false
  end
end
