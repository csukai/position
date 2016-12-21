## Preamble
This work is fundamentally _Research Code_, and consequently is a snapshot of highly specialised components that are not intended for general application. It has been released to the public domain in the hope that it may be useful for adaptation or further research.

**This code is provided as-is with no warranty or guarantee of correctness.**

If making use of this code, please be sure to cite applicable papers from the author's [publication list](http://www2.warwick.ac.uk/fac/sci/dcs/people/research/csukai/), based on the code in this repository.

## License
See LICENSE.md for details.

## Prerequisites
This work has been designed to be run using `JRuby 9.0.4.0`, with some parts also compatible with `Ruby 2.2.3` on *nix based operating systems. 

The software as a whole has no formal requirements, other than a working Ruby environment with all the gems listed in `Gemfile` installed. This can be achieved by installing [rbenv](https://github.com/sstephenson/rbenv) and [Ruby-Build](https://github.com/sstephenson/ruby-build) then using the command `rbenv install jruby-9.0.4.0`. Gems can then be installed with `gem install bundler && bundle install` from within the project directory.

## Usage
All interaction with the program is through scripts located in `/bin`, where each individual script typically performs a single task taking input files, parameters and output files/directories as parameters. Issuing `bin/script_name -h` will provide a list of parameter options for the given script.
A brief summary of what the script does can be found within the files themselves.

## Input Files
Many scripts require input files in particular formats. All input files must be YAML files (unless specified otherwise) with particular properties.

##### *Trajectory* files
Must contain a single array of hashes, where each hash must have keys `:latitude`, `:longitude`, `:timestamp` and `:accuracy`. Note that these all begin with `:` (and are therefore Ruby symbols). E.g.:

```
---
- :latitude: !ruby/object:BigDecimal '0:12.3982938'
  :longitude: !ruby/object:BigDecimal '0:-2.3849384'
  :timestamp: 2015-11-01 19:23:36.000000000 Z
  :accuracy: 15.0
- :latitude ...
```

Also note that the array is assumed to be ordered temporally. Each *Trajectory* file belongs to exactly 1 entity and cannot contain points from multiple entities/users. The usage of BigDecimal is recommended for precision, however, other formats should work providing that they can be cast to a BigDecimal.

Generating trajectory files from the MDC dataset is achieved using the scripts in `bin/datasets`.

## Output Files
Output files are typically YAML files.