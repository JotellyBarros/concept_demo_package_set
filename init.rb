

FileUtils.mkdir_p File.join(Autoproj.prefix, 'lib', 'python3.5', 'dist-packages')
FileUtils.mkdir_p File.join(Autoproj.prefix, 'lib', 'python3.5', 'site-packages')

Autoproj.env_add_path 'PYTHONPATH', File.join(Autoproj.prefix, 'lib', 'python3.5', 'dist-packages')
Autoproj.env_add_path 'PYTHONPATH', File.join(Autoproj.prefix, 'lib', 'python3.5', 'site-packages')


require_relative 'autoproj/code_integration'
require_relative 'autobuild/dsl'

Autoproj::CodeIntegration.instance.setup_integration
