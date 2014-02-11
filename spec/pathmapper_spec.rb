#Pathmapper is hard to test because it is difficult to mock Dir/Pathname/File etc...
require "spec_helper"
require "fusefs/pathmapper"
require 'tmpdir'
require 'pathname'
require 'sys/filesystem'
require 'ffi-xattr/extensions'

class PMFixture
    attr_reader :tmpdir

    def initialize()
        #Note - these names define the filesystem stats so if you change them those tests will break
    end

    def tmpdir
        @tmpdir ||= Pathname.new(Dir.mktmpdir("rfusefs_pathmapper"))
    end

    def real_path(file)
        tmpdir + file
    end

    def pathmap(file,mapped_path, content = mapped_path, options = {})
        real_file = tmpdir + file
        real_file.open("w") do |f|
            f << content
        end
        fs.map_file(real_file,mapped_path,options)
    end

    def fs
        @fs ||= FuseFS::PathMapperFS.new()
    end

    def mount()
        return @mountpoint if @mountpoint
        @mountpoint = Pathname.new(Dir.mktmpdir("rfusefs_pathmapper_mnt"))
        FuseFS.mount(fs,@mountpoint)
        sleep(0.5)
        @mountpoint
    end

    def cleanup
        if @mountpoint
            FuseFS.unmount(@mountpoint)
            sleep(0.5)
            FileUtils.rmdir(@mountpoint)
        end
        FileUtils.rm_r(@tmpdir)
    end
end


describe FuseFS::PathMapperFS do

    let(:fixture) { PMFixture.new() }
    let(:pathmap_fs) { fixture.fs }
    let(:tmpdir) { fixture.tmpdir }
    let(:mountpoint) { fixture.mount }

    before(:each) do
        fixture.pathmap("hello.txt","/textfiles/hello")
        fixture.pathmap("mysong.mp3","/artist/album/mysong.mp3")
        fixture.pathmap("apicture.jpeg","/pictures/201103/apicture.jpg")
    end

    after(:each) do
        fixture.cleanup
    end

    context "fusefs api" do

        it "maps files and directories" do
            pathmap_fs.directory?("/").should be_true
            pathmap_fs.directory?("/textfiles").should be_true
            pathmap_fs.directory?("/pictures/201103").should be_true
            pathmap_fs.file?("/textfiles/hello").should be_true
            pathmap_fs.directory?("/textfiles/hello").should be_false
            pathmap_fs.file?("/artist/album/mysong.mp3").should be_true
            pathmap_fs.directory?("/artist/album/mysong.mp3").should be_false
            pathmap_fs.file?("/some/unknown/path").should be_false
            pathmap_fs.directory?("/some/unknown/path").should be_false
        end

        it "lists the mapped contents of directories" do
            pathmap_fs.contents("/").should =~ [ "textfiles","artist","pictures" ]
            pathmap_fs.contents("/artist").should =~ [ "album" ]
            pathmap_fs.contents("/textfiles").should =~ [ "hello" ]
        end

        it "reports the size of a file" do
            pathmap_fs.size("/textfiles/hello").should == 16
        end

        it "reads the contents of a file" do
            pathmap_fs.read_file("/textfiles/hello").should == "/textfiles/hello"
        end

        it "does not allow writes" do
            pathmap_fs.can_write?("/textfiles/hello").should be_false
        end

        it "reports the atime,mtime and ctime of the mapped file" do
            atime,mtime,ctime = pathmap_fs.times("/pictures/201103/apicture.jpg")
            picture = tmpdir + "apicture.jpeg"
            atime.should == picture.atime()
            mtime.should == picture.mtime()
            ctime.should == picture.ctime()
        end

        context "with extended attributes" do
            let (:hello_realpath) {fixture.real_path("hello.txt")}
            let (:hello_xattr) { Xattr.new(hello_realpath) }
            let (:pm_file_xattr) { pathmap_fs.xattr("/textfiles/hello") }
            let (:pm_dir_xattr) { pathmap_fs.xattr("/textfiles") }

            before(:each) do
                # attribute set on real file
                hello_xattr["user.file_attr"] = "fileValue"

                # additional attribute on file
                pathmap_fs.node("/textfiles/hello")[:xattr] =
                    { "user.add_attr" => "addValue" }

                # additional attribute on directory
                pathmap_fs.node("/textfiles")[:xattr] =
                    { "user.dir_attr" => "dirValue" }

            end

            it "should list extended attributes" do
                pm_file_xattr.keys.should include("user.file_attr")
                pm_file_xattr.keys.should include("user.add_attr")
                pm_file_xattr.keys.size.should == 2
            end

            it "should read extended attributes from underlying file" do
                pm_file_xattr["user.file_attr"].should == "fileValue"
            end

            it "should read additional attributes" do
                # make sure additional attributes are not on the real file
                hello_xattr.list.should_not include("user.add_attr")

                pm_file_xattr["user.add_attr"].should == "addValue"
            end

            it "should write extended attributes to the underlying file" do
                pm_file_xattr["user.file_attr"] = "written"
                hello_xattr["user.file_attr"].should == "written"
            end

            it "should remove extended attributes from the underlying file" do
                pm_file_xattr.delete("user.file_attr")
                hello_xattr.list.should_not include("user.file_attr")
            end

            it "raise EACCES when writing to additional attributes" do
                lambda {pm_file_xattr["user.add_attr"] = "newValue"}.should raise_error(Errno::EACCES)
            end

            it "raise EACCES when removing additional attributes" do
                lambda {pm_file_xattr.delete("user.add_attr")}.should raise_error(Errno::EACCES)
            end

            it "should list additional attributes from virtual directories" do
                pm_dir_xattr.keys.should include("user.dir_attr")
                pm_dir_xattr.keys.size.should == 1
            end

            it "should read additional attributes from virtual directories" do
                pm_dir_xattr["user.dir_attr"].should == "dirValue"

            end

            it "should raise EACCES when writing additional attributes on virtual directories" do
                lambda {pm_dir_xattr["user.dir_attr"] = "newValue"}.should raise_error(Errno::EACCES)
            end

            it "should raise EACCES when deleting additional attributes on virtual directories" do
                lambda {pm_dir_xattr.delete("user.dir_attr")}.should raise_error(Errno::EACCES)
            end

            it "should accept xattr as option to #map_file" do
                fixture.pathmap("mapped_xattr.txt","/textfiles/mapped_xattr","content",
                                 :xattr => { "user.xattr" => "map_file" })
                pathmap_fs.xattr("/textfiles/mapped_xattr")["user.xattr"].should == "map_file"
            end
        end

        context "filesystem statistics" do

            it "reports accumulated stats about mapped files" do
                used_space, used_nodes, max_space, max_nodes = pathmap_fs.statistics("/pictures/201103/apicture.jpg")
                used_space.should == 69
                used_nodes.should == 9
                max_space.should be_nil
                max_nodes.should be_nil
            end
        end

        context "writing to a pathmapped FS" do
            before(:each) do
                pathmap_fs.allow_write=true
                pathmap_fs.write_to("textfiles/hello","updated content")
            end

            it "updates the contents of the real file" do
                hello_path = tmpdir + "hello.txt"
                hello_path.read.should == "updated content"
            end

            it "updates the contents of the mapped file" do
                pathmap_fs.read_file("textfiles/hello").should == "updated content"
            end

            it "changes the reported file size" do
                pathmap_fs.size("textfiles/hello").should == 15
            end

            it "changes the filesystem statistics" do
                used_space, used_nodes, max_space, max_nodes = pathmap_fs.statistics("/pictures/201103/apicture.jpg")
                used_space.should == 68
            end
        end

    end

    context "a real Fuse mounted filesystem" do
        before(:each) do
            pathmap_fs.allow_write=true
        end

        it "maps files and directories" do
            (mountpoint + "textfiles").directory?.should be_true
            (mountpoint + "textfiles/hello").file?.should be_true
        end

        it "lists the mapped contents of directories" do
            (mountpoint + "textfiles").entries.should =~ pathnames(".","..","hello")
        end

        it "represents the stat information of the underlying files" do
            hellopath=(mountpoint + "textfiles/hello")
            realpath=(tmpdir + "hello.txt")
            mappedstat = hellopath.stat
            realstat = realpath.stat
            mappedstat.size.should == realstat.size
            mappedstat.atime.should == realstat.atime
            mappedstat.mtime.should == realstat.mtime
            mappedstat.ctime.should == realstat.ctime
        end

        it "reads the files" do
            hellopath= mountpoint + "textfiles/hello"
            hellopath.read.should == "/textfiles/hello"
        end

        it "writes the files" do
            hellopath= mountpoint + "textfiles/hello"
            real_path = tmpdir + "hello.txt"
            hellopath.open("w") do |f|
                f.print "updated content"
            end
            hellopath.read.should == "updated content"
            real_path.read.should == "updated content"
        end

        context "extended attributes" do
            let (:hello_realpath) {fixture.real_path("hello.txt")}
            let (:hello_xattr) { hello_realpath.xattr }
            let (:file_xattr) { (mountpoint + "textfiles/hello").xattr }
            let (:dir_xattr) { (mountpoint + "textfiles").xattr }

            before(:each) do
                # attribute set on real file
                hello_xattr["user.file_attr"] = "fileValue"

                # additional attribute on file
                pathmap_fs.node("/textfiles/hello")[:xattr] =
                    { "user.add_attr" => "addValue" }

                # additional attribute on directory
                pathmap_fs.node("/textfiles")[:xattr] =
                    { "user.dir_attr" => "dirValue" }

            end

            it "should list extended attributes" do
                file_xattr.list.should include("user.file_attr")
                file_xattr.list.should include("user.add_attr")
                file_xattr.list.size.should == 2
            end

            it "should read extended attributes from underlying file" do
                file_xattr["user.file_attr"].should == "fileValue"
            end

            it "should read additional attributes" do
                file_xattr["user.add_attr"].should == "addValue"
            end

            it "should write extended attributes to the underlying file" do
                file_xattr["user.file_attr"] = "written"
                hello_xattr["user.file_attr"].should == "written"
            end

            it "should remove extended attributes from the underlying file" do
                file_xattr.remove("user.file_attr")
                hello_xattr.list.should_not include("user.file_attr")
            end

            it "raise EACCES when writing to additional attributes" do
                lambda {file_xattr["user.add_attr"] = "newValue"}.should raise_error(Errno::EACCES)
            end

            it "raise EACCES when removing additional attributes" do
                lambda {file_xattr.remove("user.add_attr")}.should raise_error(Errno::EACCES)
            end

            it "should list additional attributes from virtual directories" do
                dir_xattr.list.should include("user.dir_attr")
                dir_xattr.list.size.should == 1
            end

            it "should read additional attributes from virtual directories" do
                dir_xattr["user.dir_attr"].should == "dirValue"
            end

            it "should raise EACCES when writing additional attributes on virtual directories" do
                lambda {dir_xattr["user.dir_attr"] = "newValue"}.should raise_error(Errno::EACCES)
            end

            it "should raise EACCES when deleting additional attributes on virtual directories" do
                lambda {dir_xattr.remove("user.dir_attr")}.should raise_error(Errno::EACCES)
            end

        end

        context "filesystem statistics" do
            before(:each) do
                fixture.pathmap("bigfile.txt","/textfiles/bigfile","x" * 2048)
            end

            it "reports stats for files" do
                statfs = Sys::Filesystem.stat(mountpoint.to_path)
                # These are fixed
                statfs.block_size.should == 1024
                statfs.fragment_size.should == 1024

                # These are dependant on the tests above creating files/directories
                statfs.files.should == 10
                statfs.files_available == 10

                # assume test are less than 1 block, so dependant on bigfile above
                statfs.blocks.should == 2
                statfs.blocks_available.should == 0
                statfs.blocks_free.should == 0
            end

            it "reports stats for files after writing" do

                (mountpoint + "textfiles/bigfile").open("w") { |f| f.print("y" * 4096) }
                statfs = Sys::Filesystem.stat(mountpoint.to_path)
                statfs.files.should == 10
                statfs.blocks.should == 4

            end

        end
    end

    context "a real Fuse mount with raw file access" do

        before(:each) do
            pathmap_fs.use_raw_file_access = true
            pathmap_fs.allow_write = true
        end

        it "reads files" do
            hello_path = (mountpoint + "textfiles/hello")
            hello_path.open do |f|
                f.seek(2)
                f.read(3).should == "ext"
            end

            hello_path.sysopen do |f|
                f.sysseek(1)
                f.sysread(3).should == "tex"
            end
        end

        it "writes files" do
            hello_path = (mountpoint + "textfiles/hello")
            real_path = tmpdir + "hello.txt"
            hello_path.open("r+") do |f|
                f.sysseek(2)
                f.syswrite("zzz")
                f.sysseek(0)
                f.sysread(6).should == "/tzzzf"
            end

            real_path.read.should == "/tzzzfiles/hello"
        end

        it "reports filesystem statistics after raw write" do
            hello_path = (mountpoint + "textfiles/hello")
            hello_path.open("w") do |f|
                f.syswrite("z" * 2048)
            end

            statfs = Sys::Filesystem.stat(mountpoint.to_path)
            statfs.blocks.should == 2
        end
    end
end
