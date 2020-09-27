# rfusefs

*   https://rubygems.org/gems/rfusefs
*   https://github.com/lwoggardner/rfusefs

[<img src="https://badge.fury.io/rb/rfusefs.png" alt="Gem Version"
/>](http://badge.fury.io/rb/rfusefs)
## DESCRIPTION

RFuseFS is a port of the [FuseFS](http://rubygems.org/gems/fusefs/) library
aimed at allowing Ruby programmers to quickly and easily create virtual
filesystems with little more than a few lines of code.

RFuseFS is api compatible with FuseFS (0.7.0)

## SYNOPSIS

FuseFS provides a layer of abstraction to a programmer who wants to create a
virtual filesystem via FUSE.

First define a virtual directory by subclassing {FuseFS::FuseDir}

See samples under /samples and also the following starter classes

*   {FuseFS::FuseDir}
*   {FuseFS::MetaDir}
*   {FuseFS::DirLink}
*   {FuseFS::PathMapperFS}
*   {FuseFS::SqliteMapperFS}


Then start your filesystem with

*   {FuseFS.main} or {FuseFS.start}


Finally to use the filesystem open up your favourite file browser/terminal and
explore the contents under <mountpoint>

Happy Filesystem Hacking!

### the hello world filesystem in 14 LOC

    require 'rfusefs'

    class HelloDir

      def contents(path)
        ['hello.txt']
      end

      def file?(path)
        path == '/hello.txt'
      end

      def read_file(path)
        "Hello, World!\n"
      end

    end

    # Usage: #{$0} mountpoint [mount_options]
    FuseFS.main() { |options| HelloDir.new }

## REQUIREMENTS:

*   FUSE (http://fuse.sourceforge.net)
*   Ruby (>= 2.5)
*   rfuse (~> 1.2)


## INSTALL:

*   gem install rfusefs

## DEVELOPERS:

After checking out the source, run:

    $ bundle install # install dependencies
    $ rake spec # run tests
    $ rake yard # generate docs

