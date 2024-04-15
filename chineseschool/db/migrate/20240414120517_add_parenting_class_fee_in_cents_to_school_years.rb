class AddParentingClassFeeInCentsToSchoolYears < ActiveRecord::Migration
  def change
    add_column :school_years, :parenting_class_fee_in_cents, :integer,  null: false, default: 0
  end
end
