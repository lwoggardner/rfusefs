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
        [ cur, File::SEPARATOR + File.join(rest) ]
      end
    end

    #   base,*rest = scan_path(path)
    # @return [Array<String>] all directory and file elements in path. Useful
    #                         when encapsulating an entire fs into one object
    def scan_path(path)
      path.scan(/[^\/]+/)
    end
  end



  # A full in-memory filesystem defined with hashes. It is writable to the
  # user that mounted it 
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
  # directory structures under it. For example, to mount a dictionary filesystem
  # (see samples/dictfs.rb), use:
  #   
  #   root.mkdir("/dict",DictFS.new())
  # 
  class MetaDir < FuseDir

    def initialize()
      @subdirs  = Hash.new(nil)
      @files    = Hash.new(nil)
    end

    def directory?(path)
      pathmethod(:directory?,path) do |filename|
        !filename || filename == "/" || @subdirs.has_key?(filename)
      end
    end
    
    def file?(path)
      pathmethod(:file?,path) do |filename|
        @files.has_key?(filename)
      end
    end
    
    #List directory contents
    def contents(path)
      pathmethod(:contents,path) do | filename |
        if !filename
          (@files.keys + @subdirs.keys).sort.uniq
        else
          @subdirs[filename].contents("/")
        end
      end
    end
    
    def read_file(path)
      pathmethod(:read_file,path) do |filename|
        @files[filename].to_s
      end
    end
    
    def size(path)
      pathmethod(:size,path) do | filename |
        return @files[filename].to_s.length 
      end
    end
    
    #can_write only applies to files... see can_mkdir for directories...
    def can_write?(path)
        # we have to recurse here because it might not be a MetaDir at
        # the end of the path, but we don't have to check it is a file
        # as the API guarantees that
        pathmethod(:can_write?,path) do |filename|
           return mount_user?
        end
    end
    
    def write_to(path,contents)
    	pathmethod(:write_to,path,contents) do |filename, filecontents |
    		@files[filename] = filecontents
        end
    end
    
    # Delete a file
    def can_delete?(path)
      pathmethod(:can_delete?,path) do |filename|
          return mount_user?
      end
    end
    
    def delete(path)
      pathmethod(:delete,path) do |filename|
        @files.delete(filename)
      end
    end
    
    
    #mkdir - does not make intermediate dirs!
    def can_mkdir?(path)
       pathmethod(:can_mkdir?,path) do |dirname|
           return mount_user?
       end
    end
    
    def mkdir(path,dir=nil)
    	pathmethod(:mkdir,path,dir) do | dirname,dirobj |
        dirobj ||= MetaDir.new
        @subdirs[dirname] = dirobj
      end
    end
    
    # Delete an existing directory make sure it is not empty
    def can_rmdir?(path)
      pathmethod(:can_rmdir?,path) do |dirname|
          return mount_user? && @subdirs.has_key?(dirname) && @subdirs[dirname].contents("/").empty?
      end
    end
    
    def rmdir(path)
      pathmethod(:rmdir,path) do |dirname|
        @subdirs.delete(dirname)
      end
    end
    
    def rename(from_path,to_path,to_fusefs = self)
       
        from_base,from_rest = split_path(from_path)

        case
        when !from_base
            # Shouldn't ever happen.
            raise Errno::EACCES.new("Can't move root")
        when !from_rest
            # So now we have a file or directory to move
            if @files.has_key?(from_base)
                return false unless can_delete?(from_base) && to_fusefs.can_write?(to_path) 
                to_fusefs.write_to(to_path,@files[from_base])
                @files.delete(from_base)
            elsif @subdirs.has_key?(from_base)
                # we don't check can_rmdir? because that would prevent us 
                # moving non empty directories
                return false unless mount_user? && to_fusefs.can_mkdir?(to_path)
                begin
                   to_fusefs.mkdir(to_path,@subdirs[from_base])
                   @subdirs.delete(from_base)
                rescue ArgumentError
                   # to_rest does not support mkdir with an arbitrary object
                   return false
                end
            else
                #We shouldn't get this either
                return false
            end
        when @subdirs.has_key?(from_base)
            begin
                if to_fusefs != self
                    #just keep recursing..
                    return @subdirs[from_base].rename(from_rest,to_path,to_fusefs)
                else
                    to_base,to_rest = split_path(to_path)
                    if from_base == to_base
                       #mv within a subdir, just pass it on
                       return @subdirs[from_base].rename(from_rest,to_rest)
                    else 
                        #OK, this is the tricky part, we want to move something further down
                        #our tree into something in another part of the tree.
                        #from this point on we keep a reference to the fusefs that owns
                        #to_path (ie us) and pass it down, but only if the eventual path
                        #is writable anyway!
                        if (file?(to_path))
                            return false unless can_write?(to_path)
                        else
                            return false unless can_mkdir?(to_path)
                        end

                        return @subdirs[from_base].rename(from_rest,to_path,self)
                    end
                end


             rescue NoMethodError
                #sub dir doesn't support rename
                return false
             rescue ArgumentError
                #sub dir doesn't support rename with additional to_fusefs argument
                return false
             end
        else
            return false
        end
    end

  private
    
    # If api method not explicitly defined above, then pass it on
    # to a potential FuseFS further down the chain
    # If that turns out to be one of us then return the default
    def method_missing(method,*args)
        if (RFuseFSAPI::API_METHODS.has_key?(method))
           pathmethod(method,*args) do 
              return RFuseFS::API_METHODS[method]
           end
        else
           super
        end
    end
    # is the accessing user the same as the user that mounted our FS?, used for
    # all write activity
    def mount_user?
        return Process.uid == FuseFS.reader_uid
    end 

    #All our FuseFS methods follow the same pattern...
    def pathmethod(method, path,*args)
      base,rest = split_path(path) 
      case
      when ! base
        #request for the root of our fs
        yield(nil,*args)
      when ! rest
        #base is the filename, no more directories to traverse
        yield(base,*args)
      when @subdirs.has_key?(base)
        #base is a subdirectory, pass it on if we can
        begin
            @subdirs[base].send(method,rest,*args)
        rescue NoMethodError
            #Oh well
            return RFuseFSAPI::API_METHODS[method]
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
        #return the default response
        return RFuseFSAPI::API_METHODS[method]
      end
    end
    
    
  end
end
