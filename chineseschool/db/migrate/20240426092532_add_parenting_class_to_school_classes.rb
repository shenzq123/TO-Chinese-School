class AddParentingClassToSchoolClasses < ActiveRecord::Migration
  def change
    add_column :school_classes, :parenting_class, :string, default: 'N'
  end
end
