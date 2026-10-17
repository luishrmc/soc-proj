from pathlib import Path

from vunit import VUnit

# Initialize VUnit from command line arguments
VU = VUnit.from_argv(compile_builtins=False)

# Add VUnit built-in libraries (OSVVM, standard libraries, etc.)
VU.add_vhdl_builtins()

# Single design library, same convention as the reference setup
LIB = VU.add_library("lib")

# Design and testbench sources (VHDL-2008, .vhdl extension)
ROOT = Path(__file__).parent
LIB.add_source_files(ROOT / "src" / "**" / "*.vhdl")
LIB.add_source_files(ROOT / "test" / "**" / "*.vhdl")

# Run the test suite
VU.main()
