switch("path", "$projectDir/../src")

switch("gc","arc")
switch("define", "debug")
switch("cc", "gcc")
switch("passC", "-O1")
switch("passC", "-ggdb")

# Basic settings
switch("overflowChecks","on")
switch("define", "no_signal_handler")
switch("debugger", "native")
switch("threads", "on")
switch("tls_emulation", "off")
