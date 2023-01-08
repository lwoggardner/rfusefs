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

    def mount(*options)
        return @mountpoint if @mountpoint
        @mountpoint = Pathname.new(Dir.mktmpdir("rfusefs_pathmapper_mnt"))
        FuseFS.mount(fs,@mountpoint,*options)
        sleep(0.5)
        @mountpoint
    end

    def cleanup
        if @mountpoint
            FuseFS.unmount(@mountpoint)
            sleep(0.1)
            FileUtils.rmdir(@mountpoint)
        end
        FileUtils.rm_r(@tmpdir)
    end
end


describe FuseFS::PathMapperFS do

    let(:fixture) { PMFixture.new() }
    let(:pathmap_fs) { fixture.fs }
    let(:tmpdir) { fixture.tmpdir }
    let(:options) { [] }
    let(:mountpoint) { fixture.mount(*options) }

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
            expect(pathmap_fs.directory?("/")).to be_truthy
            expect(pathmap_fs.directory?("/textfiles")).to be_truthy
            expect(pathmap_fs.directory?("/pictures/201103")).to be_truthy
            expect(pathmap_fs.file?("/textfiles/hello")).to be_truthy
            expect(pathmap_fs.directory?("/textfiles/hello")).to be_falsey
            expect(pathmap_fs.file?("/artist/album/mysong.mp3")).to be_truthy
            expect(pathmap_fs.directory?("/artist/album/mysong.mp3")).to be_falsey
            expect(pathmap_fs.file?("/some/unknown/path")).to be_falsey
            expect(pathmap_fs.directory?("/some/unknown/path")).to be_falsey
        end

        it "lists the mapped contents of directories" do
            expect(pathmap_fs.contents("/")).to match_array([ "textfiles","artist","pictures" ])
            expect(pathmap_fs.contents("/artist")).to match_array([ "album" ])
            expect(pathmap_fs.contents("/textfiles")).to match_array([ "hello" ])
        end

        it "reports the size of a file" do
            expect(pathmap_fs.size("/textfiles/hello")).to eq(16)
        end

        it "reads the contents of a file" do
            expect(pathmap_fs.read_file("/textfiles/hello")).to eq("/textfiles/hello")
        end

        it "does not allow writes" do
            expect(pathmap_fs.can_write?("/textfiles/hello")).to be_falsey
        end

        it "reports the atime,mtime and ctime of the mapped file" do
            atime,mtime,ctime = pathmap_fs.times("/pictures/201103/apicture.jpg")
            picture = tmpdir + "apicture.jpeg"
            expect(atime).to eq(picture.atime())
            expect(mtime).to eq(picture.mtime())
            expect(ctime).to eq(picture.ctime())
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
                expect(pm_file_xattr.keys).to include("user.file_attr")
                expect(pm_file_xattr.keys).to include("user.add_attr")
                expect(pm_file_xattr.keys.size).to eq(2)
            end

            it "should read extended attributes from underlying file" do
                expect(pm_file_xattr["user.file_attr"]).to eq("fileValue")
            end

            it "should read additional attributes" do
                # make sure additional attributes are not on the real file
                expect(hello_xattr.list).not_to include("user.add_attr")

                expect(pm_file_xattr["user.add_attr"]).to eq("addValue")
            end

            it "should write extended attributes to the underlying file" do
                pm_file_xattr["user.file_attr"] = "written"
                expect(hello_xattr["user.file_attr"]).to eq("written")
            end

            it "should remove extended attributes from the underlying file" do
                pm_file_xattr.delete("user.file_attr")
                expect(hello_xattr.list).not_to include("user.file_attr")
            end

            it "raise EACCES when writing to additional attributes" do
                expect {pm_file_xattr["user.add_attr"] = "newValue"}.to raise_error(Errno::EACCES)
            end

            it "raise EACCES when removing additional attributes" do
                expect {pm_file_xattr.delete("user.add_attr")}.to raise_error(Errno::EACCES)
            end

            it "should list additional attributes from virtual directories" do
                expect(pm_dir_xattr.keys).to include("user.dir_attr")
                expect(pm_dir_xattr.keys.size).to eq(1)
            end

            it "should read additional attributes from virtual directories" do
                expect(pm_dir_xattr["user.dir_attr"]).to eq("dirValue")

            end

            it "should raise EACCES when writing additional attributes on virtual directories" do
                expect {pm_dir_xattr["user.dir_attr"] = "newValue"}.to raise_error(Errno::EACCES)
            end

            it "should raise EACCES when deleting additional attributes on virtual directories" do
                expect {pm_dir_xattr.delete("user.dir_attr")}.to raise_error(Errno::EACCES)
            end

            it "should accept xattr as option to #map_file" do
                fixture.pathmap("mapped_xattr.txt","/textfiles/mapped_xattr","content",
                                 :xattr => { "user.xattr" => "map_file" })
                expect(pathmap_fs.xattr("/textfiles/mapped_xattr")["user.xattr"]).to eq("map_file")
            end
        end

        context "filesystem statistics" do

            it "reports accumulated stats about mapped files" do
                used_space, used_nodes, max_space, max_nodes = pathmap_fs.statistics("/pictures/201103/apicture.jpg")
                expect(used_space).to eq(69)
                expect(used_nodes).to eq(9)
                expect(max_space).to be_nil
                expect(max_nodes).to be_nil
            end
        end

        context "writing to a pathmapped FS" do
            before(:each) do
                pathmap_fs.allow_write=true
                pathmap_fs.write_to("textfiles/hello","updated content")
            end

            it "updates the contents of the real file" do
                hello_path = tmpdir + "hello.txt"
                expect(hello_path.read).to eq("updated content")
            end

            it "updates the contents of the mapped file" do
                expect(pathmap_fs.read_file("textfiles/hello")).to eq("updated content")
            end

            it "changes the reported file size" do
                expect(pathmap_fs.size("textfiles/hello")).to eq(15)
            end

            it "changes the filesystem statistics" do
                used_space, used_nodes, max_space, max_nodes = pathmap_fs.statistics("/pictures/201103/apicture.jpg")
                expect(used_space).to eq(68)
            end
        end

    end

    context "a real Fuse mounted filesystem" do
        before(:each) do
            pathmap_fs.allow_write=true
        end

        it "maps files and directories" do
            expect((mountpoint + "textfiles").directory?).to be_truthy
            expect((mountpoint + "textfiles/hello").file?).to be_truthy
        end

        it "lists the mapped contents of directories" do
            expect((mountpoint + "textfiles").entries).to match_array(pathnames(".","..","hello"))
        end

        it "represents the stat information of the underlying files" do
            hellopath=(mountpoint + "textfiles/hello")
            realpath=(tmpdir + "hello.txt")
            mappedstat = hellopath.stat
            realstat = realpath.stat
            expect(mappedstat.size).to eq(realstat.size)
            expect(mappedstat.atime).to eq(realstat.atime)
            expect(mappedstat.mtime).to eq(realstat.mtime)
            expect(mappedstat.ctime).to eq(realstat.ctime)
        end

        it "reads the files" do
            hellopath= mountpoint + "textfiles/hello"
            expect(hellopath.read).to eq("/textfiles/hello")
        end

        it "writes the files" do
            hellopath= mountpoint + "textfiles/hello"
            real_path = tmpdir + "hello.txt"
            hellopath.open("w") do |f|
                f.print "updated content"
            end
            expect(hellopath.read).to eq("updated content")
            expect(real_path.read).to eq("updated content")
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
                expect(file_xattr.list).to include("user.file_attr")
                expect(file_xattr.list).to include("user.add_attr")
                expect(file_xattr.list.size).to eq(2)
            end

            it "should read extended attributes from underlying file" do
                expect(file_xattr["user.file_attr"]).to eq("fileValue")
            end

            it "should read additional attributes" do
                expect(file_xattr["user.add_attr"]).to eq("addValue")
            end

            it "should write extended attributes to the underlying file" do
                file_xattr["user.file_attr"] = "written"
                expect(hello_xattr["user.file_attr"]).to eq("written")
            end

            it "should remove extended attributes from the underlying file" do
                file_xattr.remove("user.file_attr")
                expect(hello_xattr.list).not_to include("user.file_attr")
            end

            it "raise EACCES when writing to additional attributes" do
                expect {file_xattr["user.add_attr"] = "newValue"}.to raise_error(Errno::EACCES)
            end

            it "raise EACCES when removing additional attributes" do
                expect {file_xattr.remove("user.add_attr")}.to raise_error(Errno::EACCES)
            end

            it "should list additional attributes from virtual directories" do
                expect(dir_xattr.list).to include("user.dir_attr")
                expect(dir_xattr.list.size).to eq(1)
            end

            it "should read additional attributes from virtual directories" do
                expect(dir_xattr["user.dir_attr"]).to eq("dirValue")
            end

            it "should raise EACCES when writing additional attributes on virtual directories" do
                expect {dir_xattr["user.dir_attr"] = "newValue"}.to raise_error(Errno::EACCES)
            end

            it "should raise EACCES when deleting additional attributes on virtual directories" do
                expect {dir_xattr.remove("user.dir_attr")}.to raise_error(Errno::EACCES)
            end

        end

        context "filesystem statistics" do
            before(:each) do
                fixture.pathmap("bigfile.txt","/textfiles/bigfile","x" * 2048)
            end

            it "reports stats for files" do
                statfs = Sys::Filesystem.stat(mountpoint.to_path)
                # These are fixed
                expect(statfs.block_size).to eq(1024)
                expect(statfs.fragment_size).to eq(1024)

                # These are dependant on the tests above creating files/directories
                expect(statfs.files).to eq(10)
                statfs.files_available == 10

                # assume test are less than 1 block, so dependant on bigfile above
                expect(statfs.blocks).to eq(2)
                expect(statfs.blocks_available).to eq(0)
                expect(statfs.blocks_free).to eq(0)
            end

            it "reports stats for files after writing" do

                (mountpoint + "textfiles/bigfile").open("w") { |f| f.print("y" * 4096) }
                statfs = Sys::Filesystem.stat(mountpoint.to_path)
                expect(statfs.files).to eq(10)
                expect(statfs.blocks).to eq(4)

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
            hello_path.open('r') do |f|
                f.seek(2)
                expect(f.read(3)).to eq("ext")
            end

            hello_path.sysopen do |f|
                f.sysseek(1)
                expect(f.sysread(3)).to eq("tex")
            end
        end

        it "writes files" do
            hello_path = (mountpoint + "textfiles/hello")
            real_path = tmpdir + "hello.txt"
            hello_path.open("r+") do |f|
                f.sysseek(2)
                f.syswrite("zzz")
                f.sysseek(0)
                expect(f.sysread(6)).to eq("/tzzzf")
            end

            expect(real_path.read).to eq("/tzzzfiles/hello")
        end

        it "reports filesystem statistics after raw write" do
            hello_path = (mountpoint + "textfiles/hello")
            hello_path.open("w") do |f|
                f.syswrite("z" * 2048)
            end

            statfs = Sys::Filesystem.stat(mountpoint.to_path)
            expect(statfs.blocks).to eq(2)
        end
    end
end
