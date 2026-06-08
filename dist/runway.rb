# Canonical copy lives in saadjs/homebrew-tap as Casks/runway.rb. Kept here for
# reference; release.sh prints the version/sha256 to bump on each release.
# frozen_string_literal: true

cask "runway" do
  version "1.0"
  sha256 "6d7ca6f6814b9ce2432905dc3554827d297e6b5d5414f72c98e28226ba616d1a"

  url "https://github.com/saadjs/Runway/releases/download/v#{version}/Runway-#{version}.zip"
  name "Runway"
  desc "Menu-bar app showing Claude Code and Codex usage limits"
  homepage "https://github.com/saadjs/Runway"

  depends_on macos: :ventura

  app "Runway.app"
end
