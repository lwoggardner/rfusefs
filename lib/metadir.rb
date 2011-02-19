module FuseFS	  

# Defines convenience methods for path manipulation. You should typically inherit
# from here in your own directory projects  
  class FuseDir
    
    #   base,rest = split_path(path) 
    # @return [Array<String,String>] base,rest. base is the first directory in
    #                                path, and rest is nil> or the remaining path.
    #                                Typically if rest is not nil? you should 
    #                                recurse the paths 
    def split_path(path)
      cur, *rest = path.scan(/[^\/]+/)
      if rest.empty?
        [ cur, nil ]
      else
        [ cur, File.join(rest) ]
      end
    end

    #   base,*rest = scan_path(path)
    # @return [Array<String>] all directory and file elements in path. Useful
    #                         when encapsulating an entire fs into one object
    def scan_path(path)
      path.scan(/[^\/]+/)
    end
  end



  # A full in-memory filesystem defined with hashes. It is writable and the user
  # may create and edit files within it, as well as the programmer
  # === Usage
  #   root = Metadir.new()
  #   root.mkdir("/hello")
  #   root.write_to("/hello/world","Hello World!\n")
  #   root.write_to("/hello/everybody","Hello Everyone!\n")
  #
  #   FuseFS.start(mntpath,root)
  #
  # Because Metadir is fully recursive, you can mount your own or other defined
  # directory structures under it. For example, to mount a dictionsary filesystem
  # (see samples/dictfs.rb), use:
  #   
  #   root.mkdir("/dict",DictFS.new())
  # 
  class MetaDir < FuseDir

    # atime,mtime,ctime defaults
  	INIT_TIMES = Array.new(3,Time.now.to_i)
    @@pathmethods = { }
    
    def initialize()
      @subdirs  = Hash.new(nil)
      @files    = Hash.new(nil)
    end

    
    def directory?(path)
      pathmethod(:directory?,false,path) do |filename|
        !filename || filename == "/" || @subdirs.has_key?(filename)
      end
    end
    
    def file?(path)
      pathmethod(:file?,false,path) do |filename|
        @files.has_key?(filename)
      end
    end
    
    #List directory contents
    def contents(path)
      pathmethod(:contents,nil,path) do | filename |
        if !filename
          (@files.keys + @subdirs.keys).sort.uniq
        else
          @subdirs[filename].contents("/")
        end
      end
    end
    
    def read_file(path)
      pathmethod(:read_file,nil,path) do |filename|
        @files[filename].to_s
      end
    end
    
    def size(path)
      pathmethod(:size,0,path) do | filename |
        dir,obj = false, @files[filename]
        unless obj
          dir,obj = true,@subdirs[filename]
        end
        return obj.respond_to?(:size) ? obj.size : (dir? ? 0 : obj.to_s.length)
      end
    end
    
    def times(path)
      pathmethod(:times,INIT_TIMES,path) do |filename|
        obj =  @files[filename] || @subdirs[filename]
        return obj.respond_to?(:times) ? obj.times(path) : INIT_TIMES
      end
    end
    
    #can_write only applies to files... see can_mkdir for directories...
    def can_write?(path)
      pathmethod(:can_write?,false,path) do |filename|
        return Process.uid == FuseFS.reader_uid
      end
    end
    
    def write_to(path,contents)
    	pathmethod(:write_to,false,path,contents) do |filename, filecontents |
    		@files[filename] = filecontents
      end
    end
    
    # Delete a file
    def can_delete?(path)
      pathmethod(:can_delete?,false,path) do |filename|
        @files.has_key?(filename)
      end
    end
    
    def delete(path)
      pathmethod(:delete,nil,path) do |filename|
        @files.delete(filename)
      end
    end
    
    
    #mkdir - does not make intermediate dirs!
    def can_mkdir?(path)
      pathmethod(:can_mkdir?,false,path,dir) do |dirname,dirobj|
        dirname && !(@subdirs.has_key?(dirname) || @files.has_key?(dirname))
      end
    end
    
    def mkdir(path,dir=nil)
    	pathmethod(:mkdir,nil,path,dir) do | dirname,dirobj |
        dirobj ||= MetaDir.new
        @subdirs[dirname] = dirobj
      end
    end
    
    # Delete an existing directory. 
    def can_rmdir?(path)
      pathmethod(:can_rmdir?,false,path) do |dirname|
        @subdirs.has_key?(dirname) && @subdirs[dirname].contents.empty?
      end
    end
    
    def rmdir(path)
      pathmethod(:rmdir,nil,path) do |dirname|
        @subdirs.delete(dirname)
      end
    end
    
    def rename(from_path,to_path)
        
        unless directory?(from_path)
            return false
        end

        unless can_mkdir?(to_path)
             raise Errno::EACCES.new("No access to move #{from_path} to #{to_path}")
        end

        putdir(to_path,deldir(from_path))
    end

  private
    
    def deldir(path)
       pathmethod(:deldir,nil,path) do |dirname|
            @subdirs.delete(dirname)
       end
    end

    def putdir(path,dir)
       pathmethod(:putdir,nil,path,dir) do |dirname,dirobj|
          @subdirs[dirname] = dirobj
       end
    end

    #All our FuseFS methods follow the same pattern...
    def pathmethod(method,nosubdir, path,*args)
      base,rest = split_path(path)
      case
      when ! base
        #request for the root ofield our fs
        yield(nil,*args)
      when ! rest
        #base is the filename, no more directories to traverse
        yield(base,*args)
      when @subdirs.has_key?(base)
        #base is a subdirectory, pass it on if we can
        begin
            @subdirs[base].respond_to?(method) ? @subdirs[base].send(method,rest,*args) : nosubdir
        rescue ArgumentError
            #can_mkdir,mkdir
            if args.pop.nil?
               #possibly a default arg, try sending again with one fewer arg
               @subdirs[base].send(method,rest,*args)
            else
                #definitely not a default arg, reraise
                Kernel.raise
            end
                 
        end
      else
        return nosubdir
      end
    end
    
    
  end
end
