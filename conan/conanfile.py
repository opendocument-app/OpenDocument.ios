from conan import ConanFile
from conan.tools.apple import XcodeDeps, XcodeToolchain

class Pkg(ConanFile):
    settings = "os", "compiler", "arch", "build_type"
    options = {"configuration": ["Debug", "Debug Lite", "Release", "Release Lite"]}
    default_options = {
        "configuration": "Debug",
        "odrcore/*:shared": False,
        "odrcore/*:with_pdf2htmlEX": False,
        "odrcore/*:with_wvWare": False,
    }
    requires = "odrcore/5.0.0"

    def generate(self):
        xcode = XcodeDeps(self)
        xcode.configuration = self.options.configuration
        xcode.generate()

        tc = XcodeToolchain(self)
        tc.configuration = self.options.configuration
        tc.generate()
