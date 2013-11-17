require 'fusefs/pathmapper'
require 'sqlite3'
require 'rb-inotify'
require 'thread'

module FuseFS

    class SqliteMapperFS < PathMapperFS

        def initialize(db_path,sql,options = { },&row_mapper)
            @db_path = db_path.to_s
            @sql = sql.to_s
            @row_mapper = row_mapper
            super(options)
        end

        def mounted()
            @mutex = Mutex.new
            @cv = ConditionVariable.new
            @mounted = true

            notifier = INotify::Notifier.new()

            notifier.watch(@db_path,:modify) do |event|
                @mutex.synchronize(@cv.signal)
            end

            Thread.new { notifier.run }

            @scan_thread = Thread.new() {
                @mutex.synchronize() do
                while @mounted
                    scan()
                    @cv.wait(@mutex)
                end
                end
                notifier.stop   
            }
        end

        def unmounted()
            @mounted = false
            @mutex.synchronize { @cv.signal }
            @scan_thread.join
        end

        def scan()
            @scan ||= 0
            @scan = @scan + 1

            db = SQLite3::Database.new(@db_path)
            db.results_as_hash = true

            db.execute(@sql) do |row|
                new_path, real_path, options =  @row_mapper.call(row)
                options ||= {}
                options[:sqlite_scan_id] = @scan
                map_file(new_path, real_path, options)

            end

            cleanup() { |file_node| file_node[:sqlite_scan_id] != @scan }

        ensure
            db.close if db
        end
    end
end
