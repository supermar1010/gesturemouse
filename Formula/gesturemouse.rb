class Gesturemouse < Formula
  desc "Per-direction gesture remapper for MX Master 3S thumb button"
  homepage "https://github.com/supermar1010/gesturemouse"
  url "https://github.com/supermar1010/gesturemouse.git", using: :git, branch: "main"
  version "0.1.0"
  license "MIT"

  depends_on :macos
  depends_on xcode: ["14.0", :build]

  def install
    # Embed Info.plist into the Mach-O __TEXT,__info_plist section so the
    # binary advertises a real bundle identifier. macOS keys TCC entries
    # (Accessibility / Input Monitoring) by the designated requirement
    # derived from this identifier instead of the binary's content hash,
    # which means the granted permission survives rebuilds and version
    # bumps. System Settings also shows the friendly bundle name.
    system "swiftc",
           "gesturemouse.swift",
           "-O",
           "-Xlinker", "-sectcreate",
           "-Xlinker", "__TEXT",
           "-Xlinker", "__info_plist",
           "-Xlinker", "Info.plist",
           "-framework", "CoreGraphics",
           "-framework", "Carbon",
           "-framework", "ApplicationServices",
           "-framework", "AppKit",
           "-o", "gesturemouse"
    # Ad-hoc sign with a stable identifier so the codesign requirement is
    # bound to the bundle id rather than to per-build cdhashes. Sign in an
    # isolated directory so codesign doesn't treat the build dir as an
    # implicit bundle and emit a stray _CodeSignature folder.
    mkdir_p "build/sign"
    cp "gesturemouse", "build/sign/gesturemouse"
    system "codesign",
           "--sign", "-",
           "--identifier", "com.supermar1010.gesturemouse",
           "--force",
           "build/sign/gesturemouse"
    bin.install "build/sign/gesturemouse"
    (share/"gesturemouse").install "config.example.json"
  end

  service do
    run [opt_bin/"gesturemouse"]
    keep_alive true
    log_path var/"log/gesturemouse.log"
    error_log_path var/"log/gesturemouse.log"
  end

  test do
    assert_predicate bin/"gesturemouse", :executable?
  end
end
