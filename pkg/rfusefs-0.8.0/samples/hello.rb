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

  def size(path)
    read_file(path).size
  end
end

if __FILE__ == $0	
	require 'rfusefs'
	hellodir = HelloDir.new
	FuseFS.set_root( hellodir )

	# Mount under a directory given on the command line.
	FuseFS.mount_under ARGV.shift
	FuseFS.run
end
