# -*- coding: utf-8 -*-
require 'webrick'

require 'thor'

require "rubygems"
require "rubygems/mirror/command"
require "rubygems/mirror/fetcher"
require "rubygems/mirror/pool"

# we need to rewrite couple of methods because original doesn't give parallelism to Gem::Mirror.new
# If original is changed we are screwed. Original is found on my machine in
# ~/.rvm/gems/ruby-1.9.3-p448@rubygems-mirror-command/gems/rubygems-mirror-1.0.1/lib/rubygems/mirror/command.rb
class Gem::Commands::MirrorCommand
  attr_reader :parallelism

  def initialize(parallelism = 10)
    @parallelism = parallelism
    super 'mirror', 'Mirror a gem repository'
  end

  def execute
    config_file = File.join Gem.user_home, '.gem', '.mirrorrc'

    raise "Config file #{config_file} not found" unless File.exist? config_file

    mirrors = YAML.load_file config_file

    raise "Invalid config file #{config_file}" unless mirrors.respond_to? :each

    mirrors.each do |mir|
      raise "mirror missing 'from' field" unless mir.has_key? 'from'
      raise "mirror missing 'to' field" unless mir.has_key? 'to'

      get_from = mir['from']
      save_to = File.expand_path mir['to']

      raise "Directory not found: #{save_to}" unless File.exist? save_to
      raise "Not a directory: #{save_to}" unless File.directory? save_to

      mirror = Gem::Mirror.new(get_from, save_to, parallelism)

      say "Fetching: #{mirror.from(Gem::Mirror::SPECS_FILE_Z)}"
      mirror.update_specs

      say "Total gems: #{mirror.gems.size}"

      num_to_fetch = mirror.gems_to_fetch.size

      progress = ui.progress_reporter num_to_fetch,
                                      "Fetching #{num_to_fetch} gems"

      trap(:INFO) { puts "Fetched: #{progress.count}/#{num_to_fetch}" } if SUPPORTS_INFO_SIGNAL

      mirror.update_gems { progress.updated true }

      num_to_delete = mirror.gems_to_delete.size

      progress = ui.progress_reporter num_to_delete,
                                      "Deleting #{num_to_delete} gems"

      trap(:INFO) { puts "Fetched: #{progress.count}/#{num_to_delete}" } if SUPPORTS_INFO_SIGNAL

      mirror.delete_gems { progress.updated true }
    end
  end
end

module Rubygems
  module Mirror
    module Command
      class CLI < Thor

        DEFAULT_CONFIG = [{
              "from" => "http://production.s3.rubygems.org",
              "to" => File.join(Gem.user_home, '.gem', "rubygems"),
              "parallelism" => 10,
          }]

        BASE_FILES = [
          "latest_specs.#{Gem.marshal_version}.gz",
          "Marshal.#{Gem.marshal_version}.Z",
          "yaml",
          "quick/latest_index.rz",
          "prerelease_specs.#{Gem.marshal_version}.gz",
        ]

        GEMSPECS_DIR = "quick/Marshal.#{Gem.marshal_version}/"

        desc "fetch", "fetch all the necessary files to the server."
        def fetch(skip_existing=false)
          fetch_allgems(false)
          fetch_basefiles(false)
          fetch_gemspecs(skip_existing, false)
          exit 0 #signal successful exit
        end

        desc "server [port]", "start mirror server."
        def server(port = 4000)
          WEBrick::HTTPServer.new(:DocumentRoot => to, :Port => port).start
        end

        desc "fetch_allgems", "fetch only gems."
        def fetch_allgems(exit_successfully=true)
          config_file
          say "fetch_allgems start!", :GREEN
          Gem::Commands::MirrorCommand.new(parallelism).execute
          say "fetch_allgems end!", :GREEN
          exit 0 if exit_successfully
        end

        desc "fetch_gemspecs", "fetch only gemspec files."
        def fetch_gemspecs(skip_existing=false, exit_successfully=true)
          @pool = Gem::Mirror::Pool.new(parallelism)

          say "fetch gemspecs start!", :GREEN
          Dir::foreach(File.join(to,'gems')) do |filename|
            next if filename == "." or filename == ".."
            gem_name = File.basename filename, ".gem"
            gem_path = File.join(GEMSPECS_DIR, "#{gem_name}.gemspec.rz")
            if skip_existing && File.exist?(File.join(to,gem_path))
              say "Skipping -> #{gem_name}.gemspec.rz", :BLUE
              next
            end

            @pool.job do
              say " -> #{gem_name}.gemspec.rz", :GREEN
              _fetch(gem_path)
            end

          end

          @pool.run_til_done

          say "fetch gemspecs end!", :GREEN
          exit 0 if exit_successfully
        end

        desc "fetch_basefiles", "fetch only base files."
        def fetch_basefiles(exit_successfully=true)
          say "fetch basefiles start!", :GREEN
          BASE_FILES.each do |filename|
            say " -> #{filename}", :BLUE
            _fetch(filename)
          end
          say "fetch basefiles end!", :GREEN
          exit 0 if exit_successfully
        end

        private

        def _fetch(filename)
          @fetcher ||= Gem::Mirror::Fetcher.new
          @fetcher.fetch(File.join(from, filename), File.join(to, filename))
        end

        def parallelism
          Integer(mirror['parallelism'])
        rescue
          10
        end

        def from
          mirror['from']
        end

        def to
          mirror['to']
        end

        def mirror
          @mirror ||=
            begin
              mirrors = YAML.load_file config_file
              mirrors.first
            end
        end

        def config_file
          _config_file = File.join Gem.user_home, '.gem', '.mirrorrc'
          create_config(_config_file) unless File.exist? _config_file
          _config_file
        end

        def create_config(config_file)
          File.write(config_file, DEFAULT_CONFIG.to_yaml)
        end
      end
    end
  end
end
