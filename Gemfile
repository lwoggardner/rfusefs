source "http://rubygems.org"

LOCAL_GEM_PATH = ENV.fetch('LOCAL_GEMS', '..')

def local_gem(gem_name, **options)
  options[:path] = "#{LOCAL_GEM_PATH}/#{gem_name}" if Dir.exist?("#{LOCAL_GEM_PATH}/#{gem_name}")
  gem gem_name, **options
end

%w[ffi-libfuse rfuse].each { |g| local_gem g }

gemspec
