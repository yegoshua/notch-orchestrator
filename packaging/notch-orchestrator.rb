# The Homebrew cask, as scripts/release.sh fills it in for a release. It goes into Casks/ of the tap.
cask "notch-orchestrator" do
  version "@VERSION@"
  sha256 "@SHA256@"

  url "https://github.com/yegoshua/notch-orchestrator/releases/download/v#{version}/NotchOrchestrator.zip"
  name "Notch Orchestrator"
  desc "Claude Code sessions in the MacBook notch"
  homepage "https://github.com/yegoshua/notch-orchestrator"

  livecheck do
    url :url
    strategy :github_latest
  end

  auto_updates true
  depends_on macos: :sonoma

  app "Notch Orchestrator.app"

  # The app is not notarized, and Homebrew marks what it downloads the way a browser does, so
  # macOS would refuse to open it. The mark is taken off again; see the caveats.
  postflight do
    system_command "/usr/bin/xattr",
                   args: ["-dr", "com.apple.quarantine", "#{appdir}/Notch Orchestrator.app"]
  end

  uninstall quit: "dev.notch-orchestrator.app"

  zap trash: [
    "~/Library/Application Support/notch-orchestrator",
    "~/Library/Preferences/dev.notch-orchestrator.app.plist",
  ]

  caveats <<~EOS
    Notch Orchestrator is signed with its project's own certificate and is not
    notarized by Apple. This cask removes the quarantine mark from the app so
    that macOS opens it.

    Before removing it, choose "Remove Completely" in its menu, so that its
    hooks leave ~/.claude/settings.json.
  EOS
end
