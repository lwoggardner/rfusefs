# RFuseFS.rb
require 'fuse/fusedir'
require 'fuse/rfusefs-fuse'
require 'rfusefs/version'

# This is FuseFS compatible module built over RFuse

module FuseFS
    @mounts = { }

    # Convenience method to launch a FuseFS filesystem with nice error messages
    #
    # @param [Array<String>] argv command line arguments
    # @param [Array<Symbol>] options list of additional options
    # @param [String] option_usage describing additional option usage
    # @param [String] device a description of the device field
    # @param [String] exec the executable file
    #
    # @yieldparam [Hash<Symbol,String>] options
    #   options parsed from ARGV including...
    #     * :device - the optional mount device
    #     * :mountpoint - required mountpoint
    #     * :help - true if -h was supplied
    #
    # @yieldreturn [FuseDir] an RFuseFS filesystem
    #
    # @example
    #   MY_OPTIONS = [ :myfs ]
    #   OPTION_USAGE = "  -o myfs=VAL how to use the myfs option"
    #
    #   # Normally from the command line...
    #   ARGV = [ "some/device", "/mnt/point", "-h", "-o", "debug,myfs=aValue" ]
    #
    #   FuseFS.main(ARGV, MY_OPTIONS, OPTION_USAGE, "/path/to/somedevice", $0) do |options|
    #
    #       # options ==
    #          { :device => "some/device",
    #            :mountpoint => "/mnt/point",
    #            :help => true,
    #            :debug => true,
    #            :myfs => "aValue"
    #          }
    #
    #       fs = MyFS.new(options)
    #   end
    #
    def FuseFS.main(argv=ARGV,options=[],option_usage="",device=nil,exec=File.basename($0))
        RFuse.main(argv,options,option_usage,device,exec) do |options,argv|
            root = yield options
            FuseFS.set_root(root)
            FuseFS.mount_under(*argv)
        end
    end

    # Start the FuseFS root at mountpoint with opts.
    #
    # If not previously set, Signal traps for "TERM" and "INT" are added
    # to exit the filesystem
    #
    # @param [Object] root see {set_root}
    # @param mountpoint [String] {mount_under}
    # @param [String...] opts FUSE mount options see {mount_under}
    # @note RFuseFS extension
    # @return [void]
    def FuseFS.start(root,mountpoint,*opts)
        FuseFS.set_root(root)
        begin
            FuseFS.mount_under(mountpoint,*opts)
            FuseFS.run
        ensure
            FuseFS.unmount()
        end
    end

    # Forks {FuseFS.start} so you can access your filesystem with ruby File
    # operations (eg for testing).
    # @note This is an *RFuseFS* extension
    # @return [void]
    def FuseFS.mount(root,mountpoint,*opts)

        pid = Kernel.fork do
            FuseFS.start(root,mountpoint,*opts)
        end
        @mounts[mountpoint] = pid
        pid
    end

    # Unmount a filesystem
    # @param mountpoint [String] If nil?, unmounts the filesystem started with {start}
    #                            otherwise signals the forked process started with {mount}
    #                            to exit and unmount.
    # @note RFuseFS extension
    # @return [void]
    def FuseFS.unmount(mountpoint=nil)

        if (mountpoint)
            if @mounts.has_key?(mountpoint)
                pid = @mounts[mountpoint]
                Process.kill("TERM",pid)
                Process.waitpid(pid)
            else
                raise "Unknown mountpoint #{mountpoint}"
            end
        else
            #Local unmount, make sure we only try to unmount once
            if @fuse && @fuse.mounted?
                print "Unmounting #{@fuse.mountname}\n"
                @fuse.unmount()
            end
            @fuse = nil
        end
    end

    # Set the root virtual directory
    # @param root [Object] an object implementing a subset of {FuseFS::API}
    # @return [void]
    def FuseFS.set_root(root)
        @fs=Fuse::Root.new(root)
    end

    # This will cause FuseFS to virtually mount itself under the given path. {set_root} must have
    # been called previously.
    # @param [String] mountpoint an existing directory where the filesystem will be virtually mounted
    # @param [Array<String>] args
    # @return [Fuse] the mounted fuse filesystem
    #  These are as expected by the "mount" command. Note in particular that the first argument
    #  is expected to be the mount point. For more information, see http://fuse.sourceforge.net
    #  and the manual pages for "mount.fuse"
    def FuseFS.mount_under(mountpoint, *args)
        @fuse = Fuse.new(@fs,mountpoint,*args)
    end

    # This is the main loop waiting on then executing filesystem operations from the
    # kernel.
    #
    # Note: Running in a separate thread is generally not useful. In particular
    #       you cannot access your filesystem using ruby File operations.
    # @note RFuseFS extension
    def FuseFS.run
        @fuse.run()
    end

    #  Exit the run loop and teardown FUSE
    #  Most useful from Signal.trap() or Kernel.at_exit()
    def FuseFS.exit
        @fuse.exit if @fuse
    end

    # @return [Fixnum] the calling process uid
    #     You can use this in determining your permissions, or even provide different files
    #     for different users.
    def self.reader_uid
        Thread.current[:fusefs_reader_uid]
    end

    # @return [Fixnum] the calling process gid
    def self.reader_gid
        Thread.current[:fusefs_reader_gid]
    end

    # Not supported in RFuseFS.
    #
    # The original FuseFS had special handling for editor swap/backup files
    # which appears to be a workaround for a bug where zero length files
    # where never written to. This "bug" is fixed since RFuseFS 1.0.2
    #
    # @deprecated
    def self.handle_editor(bool)
        #do nothing
    end

end

