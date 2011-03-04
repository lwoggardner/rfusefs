module FuseFS

  # A FuseFS over an existing directory 
  class DirLink

    def initialize(dir)
      File.directory?(dir) or raise ArgumentError, "DirLink.initialize expects a valid directory!"
      @base = dir
    end

    def directory?(path)
      File.directory?(File.join(@base,path))
    end

    def file?(path)
      File.file?(File.join(@base,path))
    end

    def size(path)
      File.size(File.join(@base,path))
    end

    def contents(path)
      fn = File.join(@base,path)
      Dir.entries(fn).map { |file|
      file = file.sub(/^#{fn}\/?/,'')
      if ['..','.'].include?(file)
        nil
      else
        file
      end
      }.compact.sort
    end

    def read_file(path)
      fn = File.join(@base,path)
      if File.file?(fn)
        IO.read(fn)
      else
        'No such file'
      end
    end

  end
  
end
