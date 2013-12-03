require 'spec_helper'
require 'tmpdir'
require 'sqlite3'
require 'pathname'
require "fusefs/sqlitemapper"

class SQLFixture

    SQL = "select * from files"

    attr_reader :tmpdir
    attr_reader :db
    def initialize()
        @tmpdir = Pathname.new(Dir.mktmpdir("rfusefs_sqlitemapper"))
        @db_path = @tmpdir + "test.db"
        @db = SQLite3::Database.new(@db_path.to_s) 
        @db.execute <<-SQL
            create table files (
                real_path varchar(120),
                mapped_path varchar(120)
            );
        SQL

        pathmap("hello.txt","/textfiles/hello")
        pathmap("mysong.mp3","/artist/album/mysong.mp3")
        pathmap("apicture.jpeg","/pictures/201103/apicture.jpg")

    end

    def pathmap(real_file,mapped_path)
        real_path = (@tmpdir + real_file).to_s
        File.open(real_path,"w") do |f|
            f << mapped_path
        end
        @db.execute "insert into files values ( ?, ? )", real_path,mapped_path
    end

    def unpathmap(mapped_path)
        @db.execute("delete from files where mapped_path = ?", mapped_path)
    end

    def db_force_write
        @db.close unless @db.closed?
        @db = SQLite3::Database.new(@db_path.to_s) 
    end

    def fs
        @fs ||= FuseFS::SqliteMapperFS.new(@db_path,SQL) do |row|
            [ row['real_path'], row['mapped_path'] ]
        end
    end

    def mount()
        return @mountpoint if @mountpoint
        @mountpoint = Pathname.new(Dir.mktmpdir("rfusefs_sqlitmapper_mnt"))
        FuseFS.mount(fs,@mountpoint)
        sleep 0.5
        @mountpoint
    end

    def cleanup
        @db.close
        if @mountpoint
            FuseFS.unmount(@mountpoint) 
            FileUtils.rmdir @mountpoint
        end
        FileUtils.rm_r(@tmpdir)
    end
end
describe "SqliteMapper" do

    let(:fixture) { SQLFixture.new }
    let(:fs) { fixture.fs }

    after(:each) do
        fixture.cleanup
    end

    context "filesystem outside FUSE" do
        before(:each) do
            fs.mounted()
            sleep(0.5)
        end

        after(:each) do
            fs.unmounted()
        end

        it "should map files from a sqlite database" do
            fs.directory?("/").should be_true
            fs.directory?("/textfiles").should be_true
            fs.directory?("/pictures/201103").should be_true
            fs.file?("/textfiles/hello").should be_true
            fs.directory?("/textfiles/hello").should be_false
            fs.file?("/artist/album/mysong.mp3").should be_true
            fs.directory?("/artist/album/mysong.mp3").should be_false
            fs.file?("/some/unknown/path").should be_false
        end

        context "an updated database" do

            it "should add new files" do
                fixture.pathmap("added.txt","/textfiles/added.txt")
                fixture.db_force_write()
                sleep(0.3)
                fs.file?("/textfiles/added.txt").should be_true
            end

            it "should remove files and directories no longer mapped" do
                fixture.unpathmap("/textfiles/hello")
                fixture.db_force_write()
                sleep(0.3)
                fs.file?("/textfiles/hello").should be_false
                fs.directory?("/textfiles").should be_false
            end
        end

        context "a real Fuse filesystem" do
            before(:each) do
                fs.use_raw_file_access = true
                fs.allow_write = true
                @mountpoint = fixture.mount
            end

            it "should read files" do

                hello_path = (@mountpoint + "textfiles/hello")
                hello_path.open do |f|
                    f.read.should == "/textfiles/hello"
                end
            end

        end
    end
end
