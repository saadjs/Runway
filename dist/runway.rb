# Homebrew cask for Runway. Copy/commit this to saadjs/homebrew-tap as
# Casks/runway.rb. release.sh prints the version/sha256/url to fill in.
#
#   brew install --cask saadjs/tap/runway
cask "runway" do
  version "1.0"
  sha256 "6d7ca6f6814b9ce2432905dc3554827d297e6b5d5414f72c98e28226ba616d1a"

  url "https://github.com/saadjs/Runway/releases/download/v#{version}/Runway-#{version}.zip"
  name "Runway"
  desc "Menu-bar app showing Claude Code and Codex usage limits"
  homepage "https://github.com/saadjs/Runway"

  depends_on macos: ">= :ventura"

  app "Runway.app"

  zap trash: [
    "~/Library/Caches/app.runway",
    "~/Library/Preferences/app.runway.plist",
  ]
end
