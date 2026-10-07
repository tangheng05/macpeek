cask "macpeek" do
  version "@VERSION@"
  sha256 "@SHA256@"

  url "https://github.com/tangheng05/macpeek/releases/download/v#{version}/Macpeek.zip"
  name "Macpeek"
  desc "Menu bar VPN status and system monitor"
  homepage "https://github.com/tangheng05/macpeek"

  depends_on macos: :tahoe

  app "Macpeek.app"

  # The app isn't notarized; this skips the "Open Anyway" step.
  postflight_steps do
    run "/usr/bin/xattr",
        args:           ["-dr", "com.apple.quarantine", "/Applications/Macpeek.app"],
        must_succeed:   false,
        writable_paths: ["Macpeek.app"],
        writable_base:  :appdir
  end

  uninstall quit: "io.github.tangheng05.macpeek"

  zap trash: "~/Library/Preferences/io.github.tangheng05.macpeek.plist"
end
