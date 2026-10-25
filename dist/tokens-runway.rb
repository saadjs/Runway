# Reference copy; the canonical cask is Casks/tokens-runway.rb in saadjs/homebrew-tap.
# frozen_string_literal: true

cask "tokens-runway" do
  version "1.1"
  sha256 "6fb3a4c760a387a4da3c47e767fef6308c9a0362b5546e980f4355202986d743"

  url "https://github.com/saadjs/Runway/releases/download/v#{version}/Runway-#{version}.zip"
  name "Runway"
  desc "Menu-bar app showing Claude Code and Codex usage limits"
  homepage "https://github.com/saadjs/Runway"

  depends_on macos: :ventura

  app "Runway.app"
end
