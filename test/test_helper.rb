$: << "."
$: << "lib"

ENV['RACK_ENV'] = 'test'

require "test/unit"
require "gin"
