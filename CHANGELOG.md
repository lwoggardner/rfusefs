2.0.0 / 2023-01 DEPRECATED
---------------
  * require rfuse >= 2.0.0
  * require Ruby >= 2.7
  * release via Github Actions

1.1.1 / 2020-11
---------------
  * fix gemspec
  
1.1.0 / 2020-10
---------------

 * With rfuse ~> 1.2
 * Requires Ruby 2.5+
 * Release via Travis CI

1.0.3 / 2014-12-22
----------------------

 * Pushed some internals up to RFuse
 * Allow filesystems to implement signal handlers

1.0.1 / 2013-12-19
------------------

 * Add FuseFS.main to create pretty usage messages
 * Support extended attributes in filesystems
 * Updates and cleanup of PathMapperFS
 * Provide SqliteMapperFS

1.0.0 / 2012-08-07
------------------

 * Depend on new rfuse 1.0.0, Ruby 1.9
 * API breaking changes
 * order of arguments to {FuseFS.mount}, {FuseFS.start} changed 
    to account for better option handling in RFuse

0.8.0 / 2011-02-19
------------------

* Initial port from fusefs

  * Improved raw methods
  * new "times" api for including atime,mtime,ctime in stat results
  * metadir allow mv directories
  * includes PathMapperFS

