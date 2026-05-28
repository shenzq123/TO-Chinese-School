# SQLite Database Query Helper
# Usage: ruby lib/db_query.rb [table_name] [limit]
#
# Examples:
#   ruby lib/db_query.rb student_fee_payments
#   ruby lib/db_query.rb people 10
#   ruby lib/db_query.rb                     # Shows all tables

require 'sqlite3'

db_path = 'db/development.sqlite3'
db = SQLite3::Database.new(db_path)
db.results_as_hash = true

table_name = ARGV[0]
limit = ARGV[1] ? ARGV[1].to_i : 10

if table_name.nil?
  # Show all tables
  puts "=== 所有表 ==="
  tables = db.execute("SELECT name FROM sqlite_master WHERE type='table' ORDER BY name")
  tables.each do |row|
    count = db.get_first_value("SELECT COUNT(*) FROM #{row['name']}")
    puts "#{row['name']}: #{count} rows"
  end
else
  # Show table structure
  puts "=== #{table_name} 表结构 ==="
  columns = db.execute("PRAGMA table_info(#{table_name})")
  columns.each do |col|
    puts "  #{col['name']} (#{col['type']})"
  end

  # Show sample data
  puts "\n=== #{table_name} 前 #{limit} 条记录 ==="
  rows = db.execute("SELECT * FROM #{table_name} LIMIT #{limit}")
  if rows.empty?
    puts "  (空表)"
  else
    # Print header
    puts "  " + rows.first.keys.reject { |k| k.is_a?(Integer) }.join(" | ")
    puts "  " + "-" * 60
    rows.each do |row|
      values = row.reject { |k, v| k.is_a?(Integer) }.values.map do |v|
        v.nil? ? "NULL" : v.to_s[0..20]
      end
      puts "  " + values.join(" | ")
    end
  end

  # Show total count
  count = db.get_first_value("SELECT COUNT(*) FROM #{table_name}")
  puts "\n总记录数: #{count}"
end

db.close