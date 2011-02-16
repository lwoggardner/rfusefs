#!/usr/bin/env ruby
#
# RailsFS, as written by _why_the_lucky_stiff
#
# Full instructions:
#   http://redhanded.hobix.com/inspect/railsfsAfterACoupleMinutesOfToolingWithFuseWhoa.html
#
=begin
Instructions cut and paste from _why's blog:

Save the railfs.rb script as script/filesys in your Rails app. (If you'd
rather not cut-and-paste the above, it's here.)

Now, run mkdir ~/railsmnt. Then, script/filesys ~/railsmnt. The rules are as
follows:

    * ls ~/railsmnt will give you a list of tables.
    * ls ~/railsmnt/table will list IDs from the table.
    * cat ~/railsmnt/table/id will display a record in YAML.
    * vim ~/railsmnt/table/id to edit the record in YAML!

=end

require "rubygems"
require 'fusefs'
require File.dirname(__FILE__) + '/../config/environment'

class RailsFS < FuseFS::FuseDir
    def initialize
        @classes = {}
        require 'find'
        Find.find( File.join(RAILS_ROOT, 'app/models') ) do |model| 
            if /(\w+)\.rb$/ =~ model
                model = $1
                ( @classes[model] = Kernel::const_get( Inflector.classify( model ) ) ).
                    find :first rescue @classes.delete( model )
            end
        end
    end
    def directory? path
        tname, key = scan_path path
        table = @classes[tname]
        if table.nil?; false  # /table
        elsif key;     false  # /table/id
        else; true end
    end
    def file? path
        tname, key = scan_path path
        table = @classes[tname]
        key and table and table.find( key )
    end
    def can_delete?; true end
    def can_write? path; file? path end
    def contents path
        tname, key = scan_path path
        table = @classes[tname]
        if tname.nil?; @classes.keys.sort  # /
        else; table.find( :all ).map { |o| o.id.to_s } end  # /table
    end
    def write_to path, body
        obj = YAML::load( body )
        obj.save
    end
    def read_file path
        tname, key = scan_path path
        table = @classes[tname]
        YAML::dump( table.find( key ) )
    end
end

if (File.basename($0) == File.basename(__FILE__))
    root = RailsFS.new
    FuseFS.set_root(root)
    FuseFS.mount_under(ARGV[0])
    FuseFS.run # This doesn't return until we're unmounted.
end

