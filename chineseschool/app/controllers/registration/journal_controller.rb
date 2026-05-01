require 'csv'

class Registration::JournalController < ApplicationController

  def download_teacher_and_staff_list
    school_year = SchoolYear.current_school_year
    @teacher_staff_list = []

    # Get family IDs that have students registered this year
    student_family_ids = []
    student_class_assignments = StudentClassAssignment.all(conditions: ['school_year_id = ?', school_year.id])
    student_class_assignments.each do |sca|
      families = sca.student.find_families_as_child
      families.each { |f| student_family_ids << f.id }
    end
    student_family_ids.uniq!

    # Get instructors (role contains 'Instructor')
    instructor_assignments = InstructorAssignment.all(
      conditions: ['school_year_id = ? AND role LIKE ?', school_year.id, '%Instructor'],
      include: [:instructor, :school_class]
    )
    instructor_assignments.each do |assignment|
      add_teacher_staff_entry(assignment.instructor, assignment.school_class, student_family_ids)
    end

    # Get staff
    staff_assignments = StaffAssignment.all(
      conditions: ['school_year_id = ?', school_year.id],
      include: [:person]
    )
    staff_assignments.each do |assignment|
      add_teacher_staff_entry(assignment.person, nil, student_family_ids)
    end

    # Sort by last name, first name
    @teacher_staff_list.sort! do |a, b|
      last_cmp = a[:last_name].to_s.strip.downcase <=> b[:last_name].to_s.strip.downcase
      last_cmp == 0 ? a[:first_name].to_s.strip.downcase <=> b[:first_name].to_s.strip.downcase : last_cmp
    end

    respond_to do |format|
      format.csv { send_data teacher_staff_csv,
                          type: 'text/csv; charset=utf-8',
                          filename: "teacher_staff_list_#{school_year.name.gsub(/\s+/, '_')}.csv" }
    end
  end

  def download_student_list
    school_year = SchoolYear.current_school_year
    @student_list = []

    # Get student class assignments
    student_class_assignments = StudentClassAssignment.all(
      conditions: ['school_year_id = ? AND school_class_id IS NOT NULL', school_year.id],
      include: [:student, :school_class]
    )

    # Group by family, keep student with min short_name (and min child_id for ties)
    @family_student_map = {}
    student_class_assignments.each do |sca|
      process_student_entry(sca)
    end

    # Convert to list sorted by family_id
    @family_student_map.values.sort_by { |e| e[:family_id] }.each do |entry|
      @student_list << entry
    end

    respond_to do |format|
      format.csv { send_data student_list_csv,
                          type: 'text/csv; charset=utf-8',
                          filename: "student_list_#{school_year.name.gsub(/\s+/, '_')}.csv" }
    end
  end

  private

  def add_teacher_staff_entry(person, school_class, student_family_ids)
    families_as_parent = person.find_families_as_parent
    return if families_as_parent.empty?

    family = families_as_parent.first
    return if student_family_ids.include?(family.id)

    @teacher_staff_list << {
      ccca_lifetime: family.ccca_lifetime_member ? 'Y' : '',
      first_name: person.english_first_name,
      last_name: person.english_last_name,
      chinese_name: person.chinese_name,
      class_english: school_class.try(:english_name) || '',
      class_chinese: school_class.try(:chinese_name) || '',
      short_name: school_class.try(:short_name) || '',
      location: school_class.try(:location) || ''
    }
  end

  def process_student_entry(sca)
    student = sca.student
    school_class = sca.school_class
    families = student.find_families_as_child
    return if families.empty?

    family = families.first
    short_name = school_class.short_name.to_s

    if @family_student_map[family.id].nil?
      @family_student_map[family.id] = {
        family: family,
        student: student,
        school_class: school_class,
        min_short_name: short_name,
        min_child_id: student.id,
        family_id: family.id
      }
    else
      existing = @family_student_map[family.id]
      if short_name < existing[:min_short_name]
        existing[:student] = student
        existing[:school_class] = school_class
        existing[:min_short_name] = short_name
        existing[:min_child_id] = student.id
      elsif short_name == existing[:min_short_name] && student.id < existing[:min_child_id]
        existing[:student] = student
        existing[:school_class] = school_class
        existing[:min_child_id] = student.id
      end
    end
  end

  def teacher_staff_csv
    CSV.generate do |csv|
      csv << ['CCCA Lifetime Member', 'First Name', 'Last Name', 'Chinese Name', 'Class', 'Class (Chinese)', 'Short Name', 'Location']
      @teacher_staff_list.each do |person|
        csv << [
          person[:ccca_lifetime],
          person[:first_name],
          person[:last_name],
          person[:chinese_name],
          person[:class_english],
          person[:class_chinese],
          person[:short_name],
          person[:location]
        ]
      end
    end
  end

  def student_list_csv
    CSV.generate do |csv|
      csv << ['CCCA Lifetime Member', 'Parent 1 Chinese Name', 'Parent 2 Chinese Name', 'Family ID', 'First Name', 'Last Name', 'Chinese Name', 'Class', 'Class (Chinese)', 'Short Name', 'Location']
      @student_list.each do |entry|
        family = entry[:family]
        student = entry[:student]
        school_class = entry[:school_class]
        csv << [
          family.ccca_lifetime_member ? 'Y' : '',
          family.parent_one.try(:chinese_name) || '',
          family.parent_two.try(:chinese_name) || '',
          family.id,
          student.english_first_name,
          student.english_last_name,
          student.chinese_name,
          school_class.english_name,
          school_class.chinese_name,
          school_class.short_name,
          school_class.location
        ]
      end
    end
  end
end
