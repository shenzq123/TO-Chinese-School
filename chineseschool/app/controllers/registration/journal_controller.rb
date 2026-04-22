require 'csv'

class Registration::JournalController < ApplicationController

  def download_teacher_list
    school_year_id = SchoolYear.current_school_year.id
    sql = "SELECT f.ccca_lifetime_member f1, people.english_first_name, people.english_last_name, people.chinese_name, school_classes.english_name, school_classes.chinese_name as class_chinese_name, school_classes.short_name, school_classes.location FROM people, instructor_assignments, school_classes, (select id fid, parent_one_id pid, ccca_lifetime_member from families where parent_one_id is not null union select id fid, parent_two_id parent_id, ccca_lifetime_member from families where parent_two_id is not null) f WHERE instructor_assignments.school_year_id = #{school_year_id} AND instructor_assignments.instructor_id = people.id AND instructor_assignments.school_class_id = school_classes.id and people.id=f.pid and f.fid not in (select distinct c.family_id from student_class_assignments a, people b, families_children c where a.school_year_id=#{school_year_id} and a.student_id=b.id and b.id=c.child_id) AND instructor_assignments.role LIKE '%Instructor'"
    results = ActiveRecord::Base.connection.select_all(sql)
    respond_to do |format|
      format.csv { send_data journal_csv(results, ['CCCA Lifetime Member', 'First Name', 'Last Name', 'Chinese Name', 'Class', 'Class (Chinese)', 'Short Name', 'Location']),
                          type: 'text/csv; charset=utf-8',
                          filename: "teacher_list_#{SchoolYear.current_school_year.name.gsub(/\s+/, '_')}.csv" }
    end
  end

  def download_staff_list
    school_year_id = SchoolYear.current_school_year.id
    sql = "SELECT f.ccca_lifetime_member f1, people.english_first_name, people.english_last_name, people.chinese_name FROM people, staff_assignments, (select id fid, parent_one_id pid, ccca_lifetime_member from families where parent_one_id is not null union select id fid, parent_two_id parent_id, ccca_lifetime_member from families where parent_two_id is not null) f WHERE staff_assignments.school_year_id = #{school_year_id} AND staff_assignments.person_id = people.id and people.id=f.pid and f.fid not in (select distinct c.family_id from student_class_assignments a, people b, families_children c where a.school_year_id=#{school_year_id} and a.student_id=b.id and b.id=c.child_id)"
    results = ActiveRecord::Base.connection.select_all(sql)
    respond_to do |format|
      format.csv { send_data journal_csv(results, ['CCCA Lifetime Member', 'First Name', 'Last Name', 'Chinese Name']),
                          type: 'text/csv; charset=utf-8',
                          filename: "staff_list_#{SchoolYear.current_school_year.name.gsub(/\s+/, '_')}.csv" }
    end
  end

  def download_student_list
    school_year_id = SchoolYear.current_school_year.id
    sql = "SELECT families.ccca_lifetime_member c1, p1.chinese_name p1, p2.chinese_name p2, families_children.family_id, people.english_first_name first_name, people.english_last_name last_name, people.chinese_name, school_classes.english_name, school_classes.chinese_name as class_name, school_classes.short_name, school_classes.location FROM people, student_class_assignments, school_classes,families_children, families left join people p1 on families.parent_one_id=p1.id left join people p2 on families.parent_two_id=p2.id WHERE student_class_assignments.school_year_id = #{school_year_id} AND student_class_assignments.student_id = people.id AND student_class_assignments.school_class_id = school_classes.id and families_children.child_id=people.id and families.id=families_children.family_id ORDER BY student_class_assignments.grade_id ASC"
    results = ActiveRecord::Base.connection.select_all(sql)
    respond_to do |format|
      format.csv { send_data journal_csv(results, ['CCCA Lifetime Member', 'Parent 1 Chinese Name', 'Parent 2 Chinese Name', 'Family ID', 'First Name', 'Last Name', 'Chinese Name', 'Class', 'Class (Chinese)', 'Short Name', 'Location']),
                          type: 'text/csv; charset=utf-8',
                          filename: "student_list_#{SchoolYear.current_school_year.name.gsub(/\s+/, '_')}.csv" }
    end
  end

  private

  def journal_csv(results, headers)
    CSV.generate do |csv|
      csv << headers
      results.each do |row|
        csv << row.values
      end
    end
  end
end
