# Canonical copy lives in saadjs/homebrew-tap as Casks/runway.rb. Kept here for
# reference; release.sh prints the version/sha256 to bump on each release.
# frozen_string_literal: true

cask "runway" do
  version "1.1"
  sha256 "6fb3a4c760a387a4da3c47e767fef6308c9a0362b5546e980f4355202986d743"

  url "https://github.com/saadjs/Runway/releases/download/v#{version}/Runway-#{version}.zip"
  name "Runway"
  desc "Menu-bar app showing Claude Code and Codex usage limits"
  homepage "https://github.com/saadjs/Runway"

  depends_on macos: :ventura

  app "Runway.app"
end
