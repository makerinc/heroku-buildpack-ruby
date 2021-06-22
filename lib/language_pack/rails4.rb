require "language_pack"
require "language_pack/rails3"

# Rails 4 Language Pack. This is for all Rails 4.x apps.
class LanguagePack::Rails4 < LanguagePack::Rails3
  ASSETS_CACHE_LIMIT = 52428800 # bytes

  ASSET_PATHS = %w[
    public/packs
    ~/.yarn-cache
    ~/.cache/yarn
  ]

  ASSET_CACHE_PATHS = %w[
    node_modules
    tmp/cache/webpacker
  ]

  # detects if this is a Rails 4.x app
  # @return [Boolean] true if it's a Rails 4.x app
  def self.use?
    instrument "rails4.use" do
      rails_version = bundler.gem_version('railties')
      return false unless rails_version
      is_rails4 = rails_version >= Gem::Version.new('4.0.0.beta') &&
                  rails_version <  Gem::Version.new('4.1.0.beta1')
      return is_rails4
    end
  end

  def name
    "Ruby/Rails"
  end

  def default_process_types
    instrument "rails4.default_process_types" do
      super.merge({
        "web"     => "bin/rails server -p $PORT -e $RAILS_ENV",
        "console" => "bin/rails console"
      })
    end
  end

  def compile
    instrument "rails4.compile" do
      super
    end
  end

  private

  def install_plugins
    instrument "rails4.install_plugins" do
      return false if bundler.has_gem?('rails_12factor')
      plugins = ["rails_serve_static_assets", "rails_stdout_logging"].reject { |plugin| bundler.has_gem?(plugin) }
      return false if plugins.empty?

    warn <<-WARNING
Include 'rails_12factor' gem to enable all platform features
See https://devcenter.heroku.com/articles/rails-integration-gems for more information.
WARNING
    # do not install plugins, do not call super
    end
  end

  def public_assets_folder
    "public/assets"
  end

  def default_assets_cache
    "tmp/cache/assets"
  end

  def cleanup
    # does not call super because it would return if default_assets_cache was missing
    # child classes should call super and should not use a return statement
    return if assets_compile_enabled?

    puts "Removing non-essential asset cache directories"

    FileUtils.remove_dir(default_assets_cache) if Dir.exist?(default_assets_cache)

    self.class::ASSET_CACHE_PATHS.each do |path|
      FileUtils.remove_dir(path) if Dir.exist?(path)
    end
  end

  def run_assets_precompile_rake_task
    instrument "rails4.run_assets_precompile_rake_task" do
      log("assets_precompile") do
        if Dir.glob("public/assets/{.sprockets-manifest-*.json,manifest-*.json}", File::FNM_DOTMATCH).any?
          puts "Detected manifest file, assuming assets were compiled locally"
          return true
        end

        precompile = rake.task("assets:precompile")
        return true unless precompile.is_defined?

        topic("Preparing app for Rails asset pipeline")

        load_asset_cache

        precompile.invoke(env: rake_env)

        if precompile.success?
          log "assets_precompile", :status => "success"
          puts "Asset precompilation completed (#{"%.2f" % precompile.time}s)"

          puts "Cleaning assets"
          rake.task("assets:clean").invoke(env: rake_env)

          cleanup_assets_cache
          store_asset_cache
        else
          precompile_fail(precompile.output)
        end
      end
    end
  end

  def load_asset_cache
    puts "Loading asset cache"
    @cache.load_without_overwrite public_assets_folder
    @cache.load default_assets_cache

    paths = (self.class::ASSET_PATHS + self.class::ASSET_CACHE_PATHS)
    paths.each { |path| @cache.load path }
  end

  def store_asset_cache
    puts "Storing asset cache"
    @cache.store public_assets_folder
    @cache.store default_assets_cache

    paths = (self.class::ASSET_PATHS + self.class::ASSET_CACHE_PATHS)
    paths.each { |path| @cache.store path }
  end

  def cleanup_assets_cache
    instrument "rails4.cleanup_assets_cache" do
      LanguagePack::Helpers::StaleFileCleaner.new(default_assets_cache).clean_over(ASSETS_CACHE_LIMIT)
    end
  end
end
