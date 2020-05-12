# frozen_string_literal: true

require 'autoproj'
require 'json'
require 'pathname'
require 'fileutils'
require 'autoproj/cli/main'

module Autoproj
    # Generates a .code-workspace file for easier VSCode configuration
    class CodeIntegration
        attr_accessor :workspace_name
        attr_accessor :dependencies
        attr_accessor :extensions_recommendations
        attr_accessor :cpplint_arg_root
        attr_reader :dot_vscode_dir
        attr_reader :stubs_dir
        attr_reader :python_env_path
        attr_reader :cpplint_stub_path
        attr_reader :pycodestyle_stub_path
        attr_reader :python_stub_path

        def initialize(name = 'autoproj')
            @dependencies = []
            @dependencies << 'pycodestyle-latest'
            @dependencies << 'cpplint-latest'
            @cpplint_arg_root = 'include'
            @workspace_name = name

            initialize_recommendations
            initialize_paths
        end

        def initialize_recommendations
            @extensions_recommendations = []
            @extensions_recommendations << 'mine.cpplint'
            @extensions_recommendations << 'ms-vscode.cpptools'
            @extensions_recommendations << 'ms-python.python'
            @extensions_recommendations << 'visualstudioexptteam.vscodeintellicode'
            @extensions_recommendations << 'arjones.autoproj'
            @extensions_recommendations << 'twxs.cmake'
        end

        def initialize_paths
            @dot_vscode_dir = File.join(Autoproj.root_dir, '.vscode')
            @stubs_dir = File.join(dot_vscode_dir, 'bin')
            @python_env_path = File.join(dot_vscode_dir, 'python.env')
            @cpplint_stub_path = File.join(stubs_dir, 'cpplint')
            @pycodestyle_stub_path = File.join(stubs_dir, 'pycodestyle')
            @python_stub_path = File.join(stubs_dir, 'python')
        end

        def code_workspace_path
            File.join(Autoproj.root_dir, "#{workspace_name}.code-workspace")
        end

        def empty_workspace
            {
                'folders' => [],
                'extensions' => {
                    'recommendations' => []
                },
                'settings' => {
                }
            }
        end

        def cpp_lint_settings
            {
                'cpplint.cpplintPath' => cpplint_stub_path,
                'cpplint.lineLength' => 120,
                'cpplint.root' => cpplint_arg_root,
                'cpplint.repository' => '${workspaceFolder}',
                'cpplint.headers' => [],
                'cpplint.extensions' => [
                    'cpp', 'h++', 'c', 'c++', 'hxx', 'hpp',
                    'cc', 'cxx', 'h', 'hh', 'cc'
                ]
            }
        end

        def compile_commands_path
            if Pathname.new(Autoproj.config.build_dir).absolute?
                File.join(Autoproj.config.build_dir, '${workspaceFolderBasename}',
                          'compile_commands.json')
            else
                File.join('${workspaceFolder}', Autoproj.config.build_dir,
                          'compile_commands.json')
            end
        end

        def c_cpp_settings
            {
                "C_Cpp.clang_format_fallbackStyle" => "{BasedOnStyle: Google, ColumnLimit: 120}",
                "C_Cpp.default.includePath" => [
                    "${default}",
                    "${workspaceFolder}/include"
                ],
                "C_Cpp.default.browse.path" => [
                    "${default}",
                    "${workspaceFolder}/**"
                ],
                'C_Cpp.default.compileCommands' => compile_commands_path
            }
        end

        def editor_settings
            {
                'files.autoSave' => 'afterDelay',
                'editor.detectIndentation' => false,
                '[python]' => {
                    'editor.tabSize' => 4
                },
                '[cpp]' => {
                    'editor.tabSize' => 2
                }
            }
        end

        def python_settings
            {
                'python.formatting.autopep8Args' => ['--max-line-length', '120'],
                'python.linting.pep8Args' => ['--max-line-length', '120'],
                'python.linting.enabled' => true,
                'python.pythonPath' => python_stub_path,
                'python.linting.lintOnSave' => true,
                'python.linting.pylintEnabled' => true,
                'python.linting.pep8Enabled' => true,
                'python.linting.pep8Path' => pycodestyle_stub_path,
                'python.envFile' => python_env_path,
                'python.autoComplete.extraPaths' => Autoproj.env.value('PYTHONPATH')
            }
        end

        def current_workspace
            return empty_workspace unless File.exist?(code_workspace_path)

            empty_workspace.merge(JSON.parse(File.read(code_workspace_path)))
        end

        def integration_enabled?
            Autoproj.config.get('CODE_INTEGRATION')
        end

        def update_folders?
            Autoproj.config.get('CODE_MANAGE_FOLDERS')
        end

        def incldude_pkg_sets?
            Autoproj.config.get('CODE_ADD_CONFIG')
        end

        def updated_folders(_current_folders = [])
            folders = []
            if incldude_pkg_sets?
                folders << {
                    'name' => 'autoproj (buildconf)',
                    'path' => File.join(Autoproj.root_dir, 'autoproj')
                }
            end

            installation_manifest = Autoproj::InstallationManifest.from_workspace_root(Autoproj.root_dir)
            if incldude_pkg_sets?
                folders += installation_manifest.package_sets.values.sort_by(&:name).map do |pkg_set|
                    {
                        'name' => "#{pkg_set.name} (package set)",
                        'path' => pkg_set.user_local_dir
                    }
                end
            end

            folders += installation_manifest.packages.values.sort_by(&:name).map do |pkg|
                next if Autoproj.manifest.find_autobuild_package(pkg.name).disabled?

                {
                    'name' => pkg.name,
                    'path' => pkg.srcdir
                }
            end
            folders
        end

        def updated_workspace
            code_workspace = current_workspace

            c_cpp_include_path = code_workspace['settings']['C_Cpp.default.includePath'] || []
            c_cpp_browse_path = code_workspace['settings']['C_Cpp.default.browse.path'] || []

            merged_c_cpp_settings = c_cpp_settings
            merged_c_cpp_settings['C_Cpp.default.includePath'] += c_cpp_include_path
            merged_c_cpp_settings['C_Cpp.default.browse.path'] += c_cpp_browse_path
            merged_c_cpp_settings['C_Cpp.default.includePath'].uniq!
            merged_c_cpp_settings['C_Cpp.default.browse.path'].uniq!

            [python_settings, editor_settings, merged_c_cpp_settings, cpp_lint_settings].each do |settings|
                code_workspace['settings'].merge!(settings)
            end

            code_workspace['folders'] = updated_folders(code_workspace['folders']) if update_folders?
            code_workspace['extensions']['recommendations'] = extensions_recommendations
            code_workspace
        end

        def save_updated_workspace
            File.write(code_workspace_path,
                       JSON.pretty_generate(updated_workspace))
        end

        def python_env_file
            <<~PYTHON_ENV_END
                # Automatically generated by Autoproj

                PYTHONUSERBASE="#{Autoproj.env['PYTHONUSERBASE']}"
                PYTHONPATH="#{Autoproj.env['PYTHONPATH']}"
            PYTHON_ENV_END
        end

        def cpplint_file
            <<~CPPLINT_END
                #!/bin/sh
                # Automatically generated by Autoproj

                unset AUTOPROJ_CURRENT_ROOT
                . #{File.join(Autoproj.root_dir, 'env.sh')}
                exec cpplint "$@"
            CPPLINT_END
        end

        def pycodestyle_file
            <<~PYCODESTYLE_END
                #!/bin/sh
                # Automatically generated by Autoproj

                unset AUTOPROJ_CURRENT_ROOT
                . #{File.join(Autoproj.root_dir, 'env.sh')}
                exec pycodestyle "$@"
            PYCODESTYLE_END
        end

        def python_file
            <<~PYTHON_END
                #!/bin/sh
                # Automatically generated by Autoproj

                unset AUTOPROJ_CURRENT_ROOT
                . #{File.join(Autoproj.root_dir, 'env.sh')}
                exec python "$@"
            PYTHON_END
        end

        def write_file(path, mode, contents)
            FileUtils.mkdir_p File.dirname(path)
            File.write(path, contents)
            FileUtils.chmod(mode, path)
        end

        def write_shims
            write_file(python_env_path, 0o644, python_env_file)
            write_file(cpplint_stub_path, 0o755, cpplint_file)
            write_file(pycodestyle_stub_path, 0o755, pycodestyle_file)
            write_file(python_stub_path, 0o755, python_file)
        end

        def integrate!
            return unless integration_enabled?

            write_shims
            save_updated_workspace
        end

        def setup_dependencies
            return if Autoproj.config.get('CODE_SKIP_DEPENDENCIES', false) || !integration_enabled?

            dependencies.each do |tool|
                if Autoproj.manifest.has_package?(tool)
                    Autoproj.manifest.add_package_to_layout(tool)
                else
                    Autoproj.warn "Could not find package `#{tool}`, recommended for vscode integration"
                end
            end
        end

        def register_hook
            Autoproj::CLI::Main.register_post_command_hook(:update) do
                integrate!
            end
        end

        def setup_integration
            register_hook

            Autoproj.config.declare 'CODE_INTEGRATION', 'boolean',
                                    default: 'yes',
                                    doc: ['Do you want Autoproj to generate a Visual Studio Code workspace file? (yes or no)']

            return unless integration_enabled?

            Autoproj.config.declare 'CODE_MANAGE_FOLDERS', 'boolean',
                                    default: 'no',
                                    doc: ['Should Autoproj manage folders in the Visual Studio Code workspace? (yes or no)']

            return unless update_folders?

            Autoproj.config.declare 'CODE_ADD_CONFIG', 'boolean',
                                    default: 'no',
                                    doc: ['Should the buildconf and package sets be included in your Visual Studio Code workspace? (yes or no)']

            incldude_pkg_sets?
            nil
        end

        def self.instance
            @instance ||= CodeIntegration.new
        end
    end
end
