
def make_package(name)
  import_package(name) do |pkg|
    pkg.depends_on 'python3.5'
    pkg.depends_on 'python3-pip'

    def pkg.prepare
      isolate_errors do
        build
        progress_done
      end
    end

    def pkg.build
      in_dir (srcdir) do
        run("build", Autobuild.tool(:make))
      end
    end

    def pkg.install
      in_dir (srcdir) do
        in_dir (srcdir) do
          run('install', 'make install ')
        end
      end
    end

    pkg.post_install do
      pkg.progress_start "building %s" do
        pkg.do_build
      end
      pkg.progress_start "installing %s" do
        pkg.do_install
      end
    end
  end
end
