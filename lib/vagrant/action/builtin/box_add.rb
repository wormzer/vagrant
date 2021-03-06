require "log4r"

require "vagrant/util/downloader"
require "vagrant/util/platform"

module Vagrant
  module Action
    module Builtin
      # This middleware will download a remote box and add it to the
      # given box collection.
      class BoxAdd
        def initialize(app, env)
          @app    = app
          @logger = Log4r::Logger.new("vagrant::action::builtin::box_add")
        end

        def call(env)
          @temp_path = env[:tmp_path].join("box" + Time.now.to_i.to_s)
          @logger.info("Downloading box to: #{@temp_path}")

          url = env[:box_url]
          if url !~ /^[a-z0-9]+:.*$/i
            @logger.info("No protocol found on box URL, assuming file:")
            url = "file:#{url}"
          end

          downloader_options = {}
          downloader_options[:insecure] = env[:box_download_insecure]
          downloader_options[:ui] = env[:ui]

          # Download the box to a temporary path. We store the temporary
          # path as an instance variable so that the `#recover` method can
          # access it.
          env[:ui].info(I18n.t("vagrant.actions.box.download.downloading"))
          begin
            downloader = Util::Downloader.new(url, @temp_path, downloader_options)
            downloader.download!
          rescue Errors::DownloaderInterrupted
            # The downloader was interrupted, so just return, because that
            # means we were interrupted as well.
            env[:ui].info(I18n.t("vagrant.actions.box.download.interrupted"))
            return
          end

          # Add the box
          env[:ui].info I18n.t("vagrant.actions.box.add.adding", :name => env[:box_name])
          added_box = nil
          begin
            added_box = env[:box_collection].add(
              @temp_path, env[:box_name], env[:box_provider], env[:box_force])
          rescue Vagrant::Errors::BoxUpgradeRequired
            # Upgrade the box
            env[:box_collection].upgrade(env[:box_name])

            # Try adding it again
            retry
          end

          # Call the 'recover' method in all cases to clean up the
          # downloaded temporary file.
          recover(env)

          # Success, we added a box!
          env[:ui].success(
            I18n.t("vagrant.actions.box.add.added", name: added_box.name, provider: added_box.provider))

          # Carry on!
          @app.call(env)
        end

        def recover(env)
          if @temp_path && File.exist?(@temp_path)
            File.unlink(@temp_path)
          end
        end
      end
    end
  end
end
