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

if __FILE__ == $0
	require 'rfusefs'
	hellodir = HelloDir.new
    FuseFS.start(hellodir,*ARGV)
end
