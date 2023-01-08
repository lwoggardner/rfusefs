# frozen_string_literal: true

require_relative 'version'
begin
  require 'ffi/libfuse/gem_helper'
rescue LoadError
  # allow bundle install to run
end

module RFuseFS
  # @!visibility private
  MAIN_BRANCH = 'master'
  GEM_VERSION, =
    if defined? FFI::Libfuse
      FFI::Libfuse::GemHelper.gem_version(version: VERSION, main_branch: MAIN_BRANCH)
    else
      "#{VERSION}.pre"
    end
end

