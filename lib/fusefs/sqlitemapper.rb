require 'fusefs/pathmapper'
require 'sqlite3'
require 'rb-inotify'
require 'thread'

module FuseFS

    class SqliteMapperFS < PathMapperFS

        # The database connection
        attr_reader :db

        # Maintains a count of the number of times through the scan loop
        attr_reader :scan_id

        # 
        #
        # @param [String] db_path Path to Sqlite database
        # @param [String] sql query
        # @param [Hash] options see {PathMapperFS#initialize}
        # @yieldparam [Row] row to map
        # @yieldreturn [String,String,Hash<Symbol,Object>] newpath, realpath, options
        #   * newpath - the mapped path
        #   * realpath -  path to the real file
        #   * options -  additional information to store with this path
        def initialize(db_path,sql,options = { },&row_mapper)
            @db_path = db_path.to_s
            @sql = sql.to_s
            define_singleton_method(:map_row,row_mapper) if block_given?
            super(options)
        end

        # Maps a row into a new filepath
        #
        # @param [Hash] row sqlite result hash for a row
        # @return [String,String,Hash<Symbol,Object>] newpath, realpath, options
        #   * newpath - the mapped path
        #   * realpath -  path to the real file
        #   * options -  additional information to store with this path
        # @abstract
        def map_row(row)
            raise NotImplementedError, "abstract method #{__method__} not implemented"
        end

        # FuseFS callback when the filesystem is mounted
        # performs the initial scan and starts watching the database for changes
        # @api FuseFS
        def mounted()
            @mutex = Mutex.new
            @cv = ConditionVariable.new
            @mounted = true

            notifier = start_notifier


            @scan_thread = Thread.new() do
                scan_loop(notifier)
            end
        end

        # FuseFS callback when filesystem is unmounted
        # 
        # Stops the database watching threads
        # @api FuseFS
        def unmounted()
            @mounted = false
            @mutex.synchronize { @cv.signal }
            @scan_thread.join
        end

        # Executes the sql query and passes each row to map_row (or the block passed in {#initialize})
        #
        # Subclasses can override this method for pre/post scan processing, calling super as required
        def scan()
            db.execute(@sql) do |row|
                new_path, real_path, options =  map_row(row)
                options ||= {}
                options[:sqlite_scan_id] = @scan_id
                map_file(new_path, real_path, options)
            end
            cleanup() { |file_node| file_node[:sqlite_scan_id] != @scan_id }
        end

        private

        def start_notifier
            notifier = INotify::Notifier.new()
            modified = false
            notifier.watch(@db_path,:modify, :close_write) do |event|
                modified = true if event.flags.include?(:modify)
                if event.flags.include?(:close_write) && modified
                    @mutex.synchronize {@cv.signal}
                    modified = false
                end
            end

            Thread.new { notifier.run }

            notifier
        end

        def scan_loop(notifier)
            @mutex.synchronize() do
                @scan_id = 0
                while @mounted
                    begin
                        @db = SQLite3::Database.new(@db_path,:readonly => true)
                        @db.results_as_hash = true
                        @db.busy_timeout(10000)
                        @scan_id = @scan_id + 1
                        scan()
                    rescue StandardError => e
                        puts e
                        puts e.backtrace.join("\n")
                    ensure
                        @db.close unless @db.closed?
                        @db = nil
                    end
                    @cv.wait(@mutex) 
                end
                notifier.stop   
            end
        end
    end
end
