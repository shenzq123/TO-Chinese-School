# PostgreSQL COPY format to SQLite importer
# Usage: ruby lib/pg_to_sqlite_importer.rb D:/chineseschool/dbData/registration202604190955.sql
#
# This script:
# 1. Creates the SQLite database schema from schema.rb if database is empty
# 2. Detects and adds missing columns automatically
# 3. Truncates existing tables before importing (to avoid duplicate key errors)
# 4. Imports data from PostgreSQL COPY format dump

require 'sqlite3'
require 'fileutils'

class PgToSQLiteImporter
  BATCH_SIZE = 1000

  def initialize(pg_dump_path, sqlite_db_path)
    @pg_dump_path = pg_dump_path
    @sqlite_db_path = sqlite_db_path
    @tables_imported = []
    @added_columns = []
  end

  def import
    puts "=" * 60
    puts "PostgreSQL to SQLite Importer"
    puts "=" * 60
    puts "Source: #{@pg_dump_path}"
    puts "Target: #{@sqlite_db_path}"
    puts

    # Check if database exists and has tables
    db_exists = File.exist?(@sqlite_db_path) && File.size(@sqlite_db_path) > 0

    if !db_exists
      puts "Creating database schema from schema.rb..."
      create_schema
    else
      puts "Database exists. Will truncate tables before import."
    end

    # Open database
    @db = SQLite3::Database.new(@sqlite_db_path)
    @db.results_as_hash = false

    # Disable foreign key checks during import for speed
    @db.execute("PRAGMA foreign_keys = OFF")

    # Read and parse the dump file
    File.open(@pg_dump_path, 'r:UTF-8') do |f|
      parse_copy_statements(f)
    end

    # Update SQLite sequences for auto-increment columns
    update_sequences

    # Re-enable foreign keys
    @db.execute("PRAGMA foreign_keys = ON")

    @db.close

    puts
    puts "=" * 60
    puts "Import completed successfully!"
    puts "Tables imported: #{@tables_imported.size}"
    if @added_columns.any?
      puts "Added #{@added_columns.size} missing columns:"
      @added_columns.each { |c| puts "  - #{c}" }
    end
    puts "=" * 60
  end

  private

  def create_schema
    # Run db:schema:load using rake
    env = ENV['RAILS_ENV'] || 'development'
    result = system("cd #{File.dirname(@sqlite_db_path)}/.. && rake db:schema:load RAILS_ENV=#{env}")
    unless result
      puts "Warning: Could not load schema via rake. Trying direct schema.rb load..."
      load_schema_directly
    end
  end

  def load_schema_directly
    # Alternative: read schema.rb and execute directly
    schema_path = File.join(File.dirname(@sqlite_db_path), 'schema.rb')
    if File.exist?(schema_path)
      db = SQLite3::Database.new(@sqlite_db_path)
      schema_content = File.read(schema_path)
      # This is a simplified approach - rake db:schema:load is preferred
      puts "Please run 'rake db:schema:load' manually if schema creation fails."
      db.close
    end
  end

  def get_table_columns(table_name)
    result = @db.execute("PRAGMA table_info(#{table_name})")
    result.map { |row| row[1] }  # Column name is at index 1
  end

  def parse_copy_statements(file)
    current_table = nil
    columns = []
    batch_data = []
    row_count = 0
    total_rows = 0

    while line = file.gets
      # Check for COPY statement
      if line =~ /^COPY public\.(\w+)\s+\(([^)]+)\)\s+FROM stdin;/
        current_table = $1
        columns = $2.split(', ').map(&:strip)

        # Check for missing columns and add them
        existing_cols = get_table_columns(current_table)
        columns.each_with_index do |col, idx|
          unless existing_cols.include?(col)
            add_missing_column(current_table, col, idx, columns)
          end
        end

        # Truncate table before import (to avoid duplicate keys)
        truncate_table(current_table)

        puts "\nImporting: #{current_table} (#{columns.size} columns)"
        row_count = 0
        batch_data = []
        next
      end

      # Check for end of COPY data
      if line =~ /^\\\./
        if current_table && batch_data.any?
          insert_batch(current_table, columns, batch_data)
          total_rows += row_count
          puts "  -> #{row_count} rows"
          @tables_imported << current_table
        end
        current_table = nil
        columns = []
        batch_data = []
        next
      end

      # Process data row
      if current_table && !line.strip.empty?
        values = parse_copy_line(line)
        batch_data << values
        row_count += 1

        if batch_data.size >= BATCH_SIZE
          insert_batch(current_table, columns, batch_data)
          print "."  # Progress indicator
          batch_data = []
        end
      end
    end

    puts "\n\nTotal rows imported: #{total_rows}"
  end

  def add_missing_column(table, column, idx, all_columns)
    # Guess column type based on column name and position
    col_type = guess_column_type(column, idx, all_columns)

    puts "  Adding missing column: #{table}.#{column} (#{col_type})"

    begin
      if col_type == :boolean
        @db.execute("ALTER TABLE #{table} ADD COLUMN \"#{column}\" boolean DEFAULT 0 NOT NULL")
      elsif col_type == :integer
        @db.execute("ALTER TABLE #{table} ADD COLUMN \"#{column}\" integer DEFAULT 0 NOT NULL")
      elsif col_type == :string
        @db.execute("ALTER TABLE #{table} ADD COLUMN \"#{column}\" varchar(255)")
      elsif col_type == :text
        @db.execute("ALTER TABLE #{table} ADD COLUMN \"#{column}\" text")
      elsif col_type == :date
        @db.execute("ALTER TABLE #{table} ADD COLUMN \"#{column}\" date")
      elsif col_type == :datetime
        @db.execute("ALTER TABLE #{table} ADD COLUMN \"#{column}\" datetime")
      elsif col_type == :float
        @db.execute("ALTER TABLE #{table} ADD COLUMN \"#{column}\" float")
      else
        @db.execute("ALTER TABLE #{table} ADD COLUMN \"#{column}\" varchar(255)")
      end
      @added_columns << "#{table}.#{column}"
    rescue SQLite3::Exception => e
      puts "  Warning: Could not add column #{column}: #{e.message}"
    end
  end

  def guess_column_type(column, idx, all_columns)
    # Infer type from column name patterns
    case column
    when /_in_cents$/
      :integer
    when /_date$/
      :date
    when /^is_/, /_flag$/
      :boolean
    when /_count$/
      :integer
    when /_id$/
      :integer
    when /^created_at$/, /^updated_at$/
      :datetime
    when /^description$/, /^note$/, /^response_dump$/
      :text
    when /_score$/, /^total_score$/
      :float
    when /^auto_/, /^registered$/, /^paid$/, /^active$/, /^credit$/, /^early_registration$/,
         /^multiple_child_discount$/, /^pre_k_discount$/, /^prorate_/, /^instructor_discount$/,
         /^staff_discount$/, /^ccca_lifetime_member$/, /^request_in_person$/,
         /^progress_award$/, /^spirit_award$/, /^attendance_award$/, /^talent_award$/,
         /^excellence_award$/, /^mixed_gender$/, /^filler$/, /^pair_winner$/
      :boolean
    when /^name$/, /^chinese_name$/, /^english_name$/, /^short_name$/, /^street$/, /^city$/,
         /^state$/, /^zipcode$/, /^phone$/, /^email$/, /^username$/, /^controller$/, /^action$/,
         /^status_code$/, /^gender$/, /^payment_method$/, /^check_number$/, /^native_language$/,
         /^school_class_type$/, /^role$/, /^event_type$/, /^program_type$/, /^division$/,
         /^location$/, /^jersey_number_prefix$/
      :string
    else
      # Default based on position (id is usually first)
      if idx == 0
        :integer
      else
        :string
      end
    end
  end

  def truncate_table(table_name)
    begin
      @db.execute("DELETE FROM #{table_name}")
      # Reset autoincrement if exists
      @db.execute("DELETE FROM sqlite_sequence WHERE name = ?", [table_name])
    rescue SQLite3::Exception => e
      # Table might not exist, ignore
    end
  end

  def parse_copy_line(line)
    # PostgreSQL COPY uses tab-separated values
    values = line.chomp.split("\t")  # Use double quotes for tab character
    values.map { |v| convert_value(v) }
  end

  def convert_value(value)
    # Handle NULL (\N in PostgreSQL)
    if value == '\N' || value.nil?
      return nil
    end

    # Handle empty strings - keep as empty string
    if value == ''
      return ''
    end

    # Handle boolean
    if value == 't'
      return 1
    elsif value == 'f'
      return 0
    end

    # Handle timestamps - truncate microseconds for SQLite compatibility
    if value =~ /^\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}\.\d+$/
      # Remove microseconds, keep seconds
      return value.split('.')[0]
    end

    value
  end

  def insert_batch(table, columns, batch_data)
    return if batch_data.empty?

    # Build SQL statement
    col_list = columns.map { |c| "\"#{c}\"" }.join(', ')
    placeholders = columns.map { '?' }.join(', ')
    sql = "INSERT INTO #{table} (#{col_list}) VALUES (#{placeholders})"

    # Prepare statement for batch insert
    stmt = @db.prepare(sql)

    batch_data.each do |values|
      begin
        stmt.execute(*values)
      rescue SQLite3::Exception => e
        puts "\n  ERROR inserting into #{table}: #{e.message}"
        puts "  Values: #{values[0..4].inspect}..." if values.size > 5
        puts "  Full values count: #{values.size}"
        raise e
      end
    end

    stmt.close
  end

  def update_sequences
    puts "\nUpdating auto-increment sequences..."
    @tables_imported.each do |table|
      begin
        # Get max id from the table
        result = @db.get_first_row("SELECT MAX(id) FROM #{table}")
        max_id = result&.first

        if max_id && max_id > 0
          # Update sqlite_sequence
          @db.execute("INSERT OR REPLACE INTO sqlite_sequence (name, seq) VALUES (?, ?)", [table, max_id])
        end
      rescue => e
        # Table might not have id column, skip
      end
    end
  end
end

# Main execution
if __FILE__ == $0
  if ARGV.size < 1
    puts "Usage: ruby lib/pg_to_sqlite_importer.rb <pg_dump_file> [sqlite_db_file]"
    puts ""
    puts "Example:"
    puts "  ruby lib/pg_to_sqlite_importer.rb D:/chineseschool/dbData/registration202604190955.sql"
    puts "  ruby lib/pg_to_sqlite_importer.rb D:/chineseschool/dbData/registration202604190955.sql db/development.sqlite3"
    exit 1
  end

  pg_dump_path = ARGV[0]
  sqlite_db_path = ARGV[1] || 'db/development.sqlite3'

  unless File.exist?(pg_dump_path)
    puts "Error: PostgreSQL dump file not found: #{pg_dump_path}"
    exit 1
  end

  importer = PgToSQLiteImporter.new(pg_dump_path, sqlite_db_path)
  importer.import
end