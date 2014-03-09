# -*- encoding: utf-8 -*-

Gem::Specification.new do |s|
  s.name = "gin"
  s.version = "1.2.0.20140308173042"

  s.required_rubygems_version = Gem::Requirement.new(">= 0") if s.respond_to? :required_rubygems_version=
  s.authors = ["Jeremie Castagna"]
  s.date = "2014-03-09"
  s.description = "Gin is a small Ruby web framework, built on Rack, which borrows from\nSinatra expressiveness, and targets larger applications."
  s.email = ["yaksnrainbows@gmail.com"]
  s.executables = ["gin"]
  s.extra_rdoc_files = ["History.rdoc", "Manifest.txt", "README.rdoc", "History.rdoc", "README.rdoc"]
  s.files = ["History.rdoc", "Manifest.txt", "README.rdoc", "Rakefile", "bin/gin", "lib/gin.rb", "lib/gin/app.rb", "lib/gin/asset_manifest.rb", "lib/gin/asset_pipeline.rb", "lib/gin/cache.rb", "lib/gin/config.rb", "lib/gin/constants.rb", "lib/gin/controller.rb", "lib/gin/core_ext/cgi.rb", "lib/gin/core_ext/float.rb", "lib/gin/core_ext/gin_class.rb", "lib/gin/core_ext/rack_commonlogger.rb", "lib/gin/core_ext/time.rb", "lib/gin/errorable.rb", "lib/gin/filterable.rb", "lib/gin/mountable.rb", "lib/gin/reloadable.rb", "lib/gin/request.rb", "lib/gin/response.rb", "lib/gin/router.rb", "lib/gin/rw_lock.rb", "lib/gin/stream.rb", "lib/gin/strict_hash.rb", "lib/gin/test.rb", "lib/gin/worker.rb", "public/400.html", "public/404.html", "public/500.html", "public/error.html", "public/favicon.ico", "public/gin.css", "public/gin_sm.png", "test/app/app_foo.rb", "test/app/controllers/app_controller.rb", "test/app/controllers/foo_controller.rb", "test/app/layouts/bar.erb", "test/app/layouts/foo.erb", "test/app/views/bar.erb", "test/mock_config/backend.yml", "test/mock_config/invalid.yml", "test/mock_config/memcache.yml", "test/mock_config/not_a_config.txt", "test/mock_app.rb", "test/test_app.rb", "test/test_cache.rb", "test/test_config.rb", "test/test_controller.rb", "test/test_errorable.rb", "test/test_filterable.rb", "test/test_gin.rb", "test/test_helper.rb", "test/test_request.rb", "test/test_response.rb", "test/test_router.rb", "test/test_rw_lock.rb", "test/test_test.rb", ".gemtest"]
  s.homepage = "http://yaks.me/gin"
  s.licenses = ["MIT"]
  s.rdoc_options = ["--main", "README.rdoc"]
  s.require_paths = ["lib"]
  s.rubyforge_project = "gin"
  s.rubygems_version = "2.0.6"
  s.summary = "Gin is a small Ruby web framework, built on Rack, which borrows from Sinatra expressiveness, and targets larger applications."
  s.test_files = ["test/test_app.rb", "test/test_cache.rb", "test/test_config.rb", "test/test_controller.rb", "test/test_errorable.rb", "test/test_filterable.rb", "test/test_gin.rb", "test/test_helper.rb", "test/test_request.rb", "test/test_response.rb", "test/test_router.rb", "test/test_rw_lock.rb", "test/test_test.rb"]

  if s.respond_to? :specification_version then
    s.specification_version = 4

    if Gem::Version.new(Gem::VERSION) >= Gem::Version.new('1.2.0') then
      s.add_runtime_dependency(%q<rack>, ["~> 1.1"])
      s.add_runtime_dependency(%q<rack-protection>, ["~> 1.0"])
      s.add_runtime_dependency(%q<tilt>, ["~> 1.4"])
      s.add_development_dependency(%q<rdoc>, ["~> 4.0"])
      s.add_development_dependency(%q<nokogiri>, ["~> 1.5.9"])
      s.add_development_dependency(%q<plist>, ["~> 3.1.0"])
      s.add_development_dependency(%q<bson>, ["~> 1.9.0"])
      s.add_development_dependency(%q<hoe>, ["~> 3.9"])
    else
      s.add_dependency(%q<rack>, ["~> 1.1"])
      s.add_dependency(%q<rack-protection>, ["~> 1.0"])
      s.add_dependency(%q<tilt>, ["~> 1.4"])
      s.add_dependency(%q<rdoc>, ["~> 4.0"])
      s.add_dependency(%q<nokogiri>, ["~> 1.5.9"])
      s.add_dependency(%q<plist>, ["~> 3.1.0"])
      s.add_dependency(%q<bson>, ["~> 1.9.0"])
      s.add_dependency(%q<hoe>, ["~> 3.9"])
    end
  else
    s.add_dependency(%q<rack>, ["~> 1.1"])
    s.add_dependency(%q<rack-protection>, ["~> 1.0"])
    s.add_dependency(%q<tilt>, ["~> 1.4"])
    s.add_dependency(%q<rdoc>, ["~> 4.0"])
    s.add_dependency(%q<nokogiri>, ["~> 1.5.9"])
    s.add_dependency(%q<plist>, ["~> 3.1.0"])
    s.add_dependency(%q<bson>, ["~> 1.9.0"])
    s.add_dependency(%q<hoe>, ["~> 3.9"])
  end
end
