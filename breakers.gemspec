# coding: utf-8
lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'breakers/version'

Gem::Specification.new do |spec|
  spec.name          = 'breakers'
  spec.version       = Breakers::VERSION
  spec.authors       = ['Aubrey Holland']
  spec.email         = ['aubrey@adhocteam.us']

  spec.summary       = 'Handle outages to backend systems with a Faraday middleware'
  spec.description   = 'This is a Faraday middleware that detects backend outages and reacts to them'
  spec.homepage      = 'https://github.com/department-of-veterans-affairs/breakers'
  spec.license       = 'CC0 1.0 Universal'

  spec.files = `git ls-files -z`.split("\x0").reject do |f|
    f.match(%r{^(test|spec|features)/})
  end
  spec.bindir        = 'exe'
  spec.executables   = spec.files.grep(%r{^exe/}) { |f| File.basename(f) }
  spec.require_paths = ['lib']

  spec.add_dependency 'faraday'
  spec.add_dependency 'multi_json'

  spec.add_development_dependency 'bundler'
  spec.add_development_dependency 'byebug'
  spec.add_development_dependency 'fakeredis'
  spec.add_development_dependency 'rake'
  spec.add_development_dependency 'rspec'
  spec.add_development_dependency 'rubocop'
  spec.add_development_dependency 'simplecov'
  spec.add_development_dependency 'timecop'
  spec.add_development_dependency 'webmock'
end
