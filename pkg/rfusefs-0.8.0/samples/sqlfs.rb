# sqlfs.rb
#
# The SQL-db proof of concept for FuseFS
#
# Author: Greg Millam

require "rubygems"
require 'fusefs'

require 'mysql'

class SqlFS < FuseFS::FuseDir
  class DBTable
    attr_accessor :name, :key, :fields
  end
  def initialize(host,user,pass,db)
    @sql = Mysql.connect(host,user,pass,db)
    @tables = Hash.new(nil)

    tables = @sql.query('show tables')

    tables.each do |i,|
      table = DBTable.new
      table.name = i
      table.fields = {}
      res = @sql.query("describe #{i}")
      res.each do |field,type,null,key,default,extra|
        table.fields[field] = type
        if (key =~ /pri/i)
          table.key = field
        end
      end
      @tables[i] = table if table.key
    end
  end
  def directory?(path)
    tname, key, field = scan_path(path)
    table = @tables[tname]
    case
    when tname.nil?
      true # This means "/"
    when table.nil?
      false
    when field
      false # Always a file
    when key
      res = @sql.query("SELECT #{table.key}, 1 FROM #{table.name} WHERE #{table.key} = '#{Mysql.escape_string(key)}'")
      res.num_rows > 0 # If there was a result, it exists.
    else
      true # It's just a table.
    end
  end
  def file?(path)
    tname, key, field = scan_path(path)
    table = @tables[tname]
    case
    when field.nil?
      false # Only field entries are files.
    when table.nil?
      false
    when ! @tables[tname].fields.include?(field)
      false # Invalid field.
    when field
      res = @sql.query("SELECT #{table.key}, 1 FROM #{table.name} WHERE #{table.key} = '#{Mysql.escape_string(key)}'")
      res.num_rows > 0
    end
  end
  def can_delete?(path)
    # This helps editors, but we don't really use it.
    true
  end
  def can_write?(path)
    # Since this is basically only for editing files,
    # we just call file?
    file?(path)
  end
  def contents(path)
    # since this is only called when directory? is true,
    # We'll assume valid entries.
    tname, key, field = scan_path(path)
    table = @tables[tname]
    case
    when tname.nil?
      @tables.keys.sort # Just the tables.
    when key
      table.fields.keys.sort
    else
      # I limit to 200 so 'ls' doesn't hang all the time :D
      res = @sql.query("SELECT #{table.key}, 1 FROM #{table.name} ORDER BY #{table.key} LIMIT 100")
      ret = []
      res.each do |val,one|
        ret << val if val.size > 0
      end
      ret
    end
  end
  def write_to(path,body)
    # Since this is only called after can_write?(), we assume
    # Valid fields.
    tname, key, field = scan_path(path)
    table = @tables[tname]
    res = @sql.query("UPDATE #{table.name} SET #{field} = '#{Mysql.escape_string(body)}' WHERE #{table.key} = '#{key}'")
  end
  def read_file(path)
    # Again, as this is only called after file?, assume valid fields.
    tname, key, field = scan_path(path)
    table = @tables[tname]
    res = @sql.query("SELECT #{field} FROM #{table.name} WHERE #{table.key} = '#{key}'")
    res.fetch_row[0]
  end
end

if (File.basename($0) == File.basename(__FILE__))
  if ARGV.size != 5
    puts "Usage: #{$0} <directory> <host> <user> <pass> <db>"
    exit
  end

  dirname, host, user, pass, db = ARGV

  if (! File.directory?(dirname))
    puts "#{dirname} is not a directory"
  end

  root = SqlFS.new(host,user,pass,db)

  # Set the root FuseFS
  FuseFS.set_root(root)

  # root.contents("/quotes")

  FuseFS.mount_under(dirname)
  FuseFS.run # This doesn't return until we're unmounted.
end
