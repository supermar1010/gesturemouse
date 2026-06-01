class Gesturemouse < Formula
  desc "Per-direction gesture remapper for MX Master 3S thumb button"
  homepage "https://github.com/supermar1010/gesturemouse"
  url "https://github.com/supermar1010/gesturemouse.git", using: :git, branch: "main"
  version "0.1.0"
  license "MIT"

  depends_on :macos
  depends_on xcode: ["14.0", :build]

  def install
    system "swiftc",
           "gesturemouse.swift",
           "-O",
           "-framework", "CoreGraphics",
           "-framework", "Carbon",
           "-framework", "ApplicationServices",
           "-o", "gesturemouse"
    bin.install "gesturemouse"
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
