# frozen_string_literal: true

require 'net/http'
require 'json'
require 'uri'
require 'fileutils'

module ReentrantSketchup
  module Updater
    GITHUB_REPO = 'msmiley/reentrant-sketchup'
    RELEASES_URL = "https://api.github.com/repos/#{GITHUB_REPO}/releases/latest"

    module_function

    # Compare semantic version strings. Returns -1, 0, or 1.
    def compare_versions(a, b)
      a_parts = a.split('.').map(&:to_i)
      b_parts = b.split('.').map(&:to_i)
      a_parts <=> b_parts
    end

    # Check GitHub for the latest release. Downloads and installs if newer.
    # All network I/O runs inline (called from a UI.start_timer callback)
    # so that SketchUp API calls stay on the main thread.
    # @param notify_if_current [Boolean] show a dialog even when up to date
    def check_for_update(notify_if_current: false)
      uri = URI.parse(RELEASES_URL)
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = true
      http.open_timeout = 10
      http.read_timeout = 10

      request = Net::HTTP::Get.new(uri.request_uri)
      request['Accept'] = 'application/vnd.github.v3+json'
      request['User-Agent'] = "#{PLUGIN_NAME}/#{PLUGIN_VERSION}"

      response = http.request(request)
      return unless response.is_a?(Net::HTTPSuccess)

      release = JSON.parse(response.body)
      latest_tag = release['tag_name'].to_s.sub(/^v/, '')

      if compare_versions(latest_tag, PLUGIN_VERSION) > 0
        rbz_asset = release['assets']&.find { |a| a['name'].end_with?('.rbz') }
        if rbz_asset
          prompt_update(latest_tag, rbz_asset['browser_download_url'])
        else
          UI.messagebox(
            "#{PLUGIN_NAME} v#{latest_tag} is available but has no .rbz download.\n" \
            "Visit the GitHub releases page to update manually."
          )
        end
      elsif notify_if_current
        UI.messagebox("#{PLUGIN_NAME} v#{PLUGIN_VERSION} is up to date.")
      end
    rescue StandardError => e
      UI.messagebox("Update check failed: #{e.message}") if notify_if_current
    end

    # Prompt user then download and install the .rbz
    def prompt_update(version, download_url)
      result = UI.messagebox(
        "#{PLUGIN_NAME} v#{version} is available (you have v#{PLUGIN_VERSION}).\n\n" \
        "Download and install the update?",
        MB_YESNO
      )
      return unless result == IDYES

      download_and_install(download_url)
    end

    def download_and_install(url)
      uri = URI.parse(url)
      tmp_dir = File.join(Sketchup.temp_dir, 'reentrant_sketchup_update')
      FileUtils.mkdir_p(tmp_dir)
      tmp_file = File.join(tmp_dir, 'reentrant_sketchup.rbz')

      # Follow redirects (GitHub asset URLs redirect)
      response = fetch_with_redirects(uri)

      unless response.is_a?(Net::HTTPSuccess)
        UI.messagebox("Download failed (HTTP #{response.code}).")
        return
      end

      File.binwrite(tmp_file, response.body)
      Sketchup.install_from_archive(tmp_file)
      UI.messagebox(
        "#{PLUGIN_NAME} has been updated.\n" \
        "Please restart SketchUp to complete the update."
      )
    rescue StandardError => e
      UI.messagebox("Update install failed: #{e.message}")
    ensure
      FileUtils.rm_rf(tmp_dir) if tmp_dir && File.directory?(tmp_dir)
    end

    def fetch_with_redirects(uri, limit = 5)
      raise 'Too many redirects' if limit <= 0

      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = (uri.scheme == 'https')
      http.open_timeout = 15
      http.read_timeout = 30

      request = Net::HTTP::Get.new(uri.request_uri)
      request['User-Agent'] = "#{PLUGIN_NAME}/#{PLUGIN_VERSION}"
      response = http.request(request)

      if response.is_a?(Net::HTTPRedirection)
        fetch_with_redirects(URI.parse(response['location']), limit - 1)
      else
        response
      end
    end
  end
end
